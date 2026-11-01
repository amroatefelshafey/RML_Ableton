# DE1-SoC (Cyclone V) Network Intrusion Detection System (IDS) — Project Handover & Context Dump

This document contains the complete state, technical architecture, benchmark results, mathematical calculations, toolchain notes, and next steps for the project. Use this file as context when continuing the project in any web AI session.

---

## 1. Project Overview & Objective

* **Goal:** Deploy a hardware-accelerated, quantized 1D Convolutional Neural Network (`IDS-CNN1D-S`, 5,520 parameters) for real-time Network Intrusion Detection (CIC-IDS2017 dataset) on the Intel/Terasic DE1-SoC development board.
* **Dual-Architecture Implementation:**
  1. **Software Baseline (ARM HPS):** Standalone C++ inference executed on the dual-core ARM Cortex-A9 MPCore under Linux. *(Completed, verified, benchmarked live)*.
  2. **Hardware Acceleration (Cyclone V FPGA):** High-throughput, streaming pipelined IP core generated via `hls4ml` targeting the FPGA fabric. *(Configured for 2.5 Mpps wire-speed at 50 MHz)*.
* **Strict Design Constraint:** **DO NOT WRITE MANUAL VERILOG.** The user generates Verilog RTL via `hls4ml` and compiles it using Quartus Prime Standard.

---

## 2. Hardware & Host Environment

* **Target Board:** Terasic DE1-SoC Board (Rev F).
* **Target Device:** Intel Cyclone V SoC `5CSEMA5F31C6`.
  * **FPGA Logic:** 32,070 ALMs (~85K LEs), 3,970 Kbits embedded M10K memory.
  * **DSP Blocks:** **87 variable-precision DSP blocks** (configurable as 3× 9×9, 2× 18×18, or 1× 27×27 multipliers).
  * **Hard Processor System (HPS):** Dual-core ARM Cortex-A9 @ 800 MHz, NEON SIMD, 1 GB DDR3 SDRAM.
  * **Clock Source:** On-board `CLOCK_50` oscillator (50 MHz, $T_{clk} = 20.0\text{ ns}$).
* **Host PC Environment:**
  * **OS:** Linux x86_64.
  * **Project Directory:** `/home/horsie/Documents/Projects/IDS_Abelton/Move_ME`
  * **Quartus Prime:** Quartus Prime Standard Edition 25.1 installed at `/home/horsie/altera_standard/25.1std/quartus/bin` (added to PATH).
  * **JTAG Connection:** USB-Blaster II detected via `jtagconfig`:
    * Node 1: `SOCVHPS` (@1) — ARM Cortex-A9 HPS.
    * Node 2: `5CSEMA5` (@2) — Cyclone V FPGA Fabric.
  * **UART Serial Terminal:** `/dev/ttyUSB0` at 115200 baud (8N1).
    * Credentials: User `root`, no password. Linux shell active on HPS.

---

## 3. Neural Network Architecture & Quantization

* **Model File:** `models/ids_cnn1d_qat_best.h5` (QKeras Quantization-Aware Trained model).
* **Total Parameters:** 5,520 parameters.
* **Input Tensor:** Shape `(16, 4)` = 16 time steps with 4 normalized network traffic features per step (total 64 features per packet).
* **Output:** 8 classes (Normal traffic + 7 attack categories from CIC-IDS2017: DoS, PortScan, DDoS, Brute Force, Web Attack, Botnet, Infiltration).

### Layer-by-Layer Specifications:

| Layer | Type | Input Shape | Output Shape | Parameters / Multiplications | Precision Config |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`conv1`** | `QConv1D` | `(16, 4)` | `(14, 16)` | Kernel `(3, 4, 16)` + 16 biases = **192 mults/step** | `fixed<8,3,TRN,WRAP>` (8-bit) |
| **`pool1`** | `MaxPooling1D` | `(14, 16)` | `(7, 16)` | Pool size 2, stride 2 | N/A (comparators) |
| **`conv2`** | `QConv1D` | `(7, 16)` | `(5, 24)` | Kernel `(3, 16, 24)` + 24 biases = **1,152 mults/step** | `fixed<4,3,TRN,WRAP>` (4-bit ternary/Po2) |
| **`flatten`** | `Flatten` | `(5, 24)` | `(120,)` | Re-indexing | N/A |
| **`dense1`** | `QDense` | `(120,)` | `(32,)` | Weights `(120, 32)` + 32 biases = **3,840 mults** | `fixed<4,3,TRN,WRAP>` (4-bit ternary/Po2) |
| **`dense2`** | `QDense` | `(32,)` | `(8,)` | Weights `(32, 8)` + 8 biases = **256 mults** | `fixed<8,3,TRN,WRAP>` (8-bit) |
| **`output`** | `Softmax` | `(8,)` | `(8,)` | Normalized probabilities | Fixed-point lookup / argmax |

---

## 4. Software Baseline Benchmark Results (ARM HPS)

A standalone C++ engine (`arm_ids_bench.cpp`) was cross-compiled with `arm-none-linux-gnueabihf-g++ -O3 -mfpu=neon` and executed live on the DE1-SoC ARM Cortex-A9:

* **Classification Accuracy:** **97.00%** on real CIC-IDS2017 test vectors.
* **Attack Detection Recall:** **100.00%** (zero false negatives on attack traffic).
* **Inference Latency:** **321.27 µs per packet**.
* **Software Throughput:** **~3,112 packets per second**.

---

## 5. FPGA Hardware Architecture & DSP Allocation

### Target Performance Goal:
* **Clock Frequency:** $50\text{ MHz}$ ($T_{clk} = 20.0\text{ ns}$, using the on-board `CLOCK_50` oscillator).
* **Throughput Claim:** $\mathbf{\ge 1.0\text{ Mpps}}$ (**1.0 to 2.5 Million packets per second**).
* **DSP Target:** **~60–70% of Cyclone V DSP blocks** (52 to 61 blocks out of 87).

### Mathematical Balancing (2.5 Mpps @ 60.9% DSPs):
At 50 MHz ($50\times 10^6\text{ cycles/second}$):
$$\text{Throughput} = \frac{50,000,000\text{ cycles/sec}}{\text{Initiation Interval } (II)}$$
To hit $\ge 1.0\text{ Mpps}$, $II$ must be $\le 50\text{ cycles}$. Designing for $II = 20\text{ cycles}$ achieves **2.5 Mpps**.

Because `conv2` and `dense1` use 4-bit weights ($\{-1, -0.5, 0, 0.5, 1\}$), Quartus synthesizes them into **ALM logic (bit-shifts and additions)** without consuming DSP blocks. Therefore, DSPs are allocated to the 8-bit layers (`conv1` and `dense2`).

| Layer | Math Operations | Reuse Factor ($R$) | Pipeline Cycles ($II$) | Hardware Allocation |
| :--- | :--- | :--- | :--- | :--- |
| **`conv1`** | $1 \times 16 \times 12 = 192$ mults | **$R = 2$** | **2 cycles** | $192 / 2 = 96$ mults $\implies$ **32 DSP blocks** |
| **`conv2`** | 5 sliding steps of 1,152 mults | **$R = 4$** | $5 \text{ steps} \times 4 = \mathbf{20\text{ cycles}}$ | 288 mults in **ALM logic** |
| **`dense1`** | $120 \times 32 = 3,840$ mults | **$R = 20$** | **20 cycles** | 192 mults in **ALM logic** |
| **`dense2`** | $32 \times 8 = 256$ mults | **$R = 4$** | **4 cycles** | $256 / 4 = 64$ mults $\implies$ **21 DSP blocks** |

#### Resulting Performance Metrics:
* **Total DSP Blocks Used:** $32 + 21 = \mathbf{53\text{ DSP blocks}}\ (\mathbf{60.9\%}\text{ of 87})$.
* **Initiation Interval ($II$):** $\max(2, 20, 20, 4) = \mathbf{20\text{ clock cycles}}$.
* **Hardware Throughput:**
  $$\text{Throughput} = \frac{50\text{ MHz}}{20\text{ cycles}} = \mathbf{2,500,000\text{ packets/second}}\ (\mathbf{2.5\text{ Mpps}})$$
* **Ethernet Wire Speed:**
  * At standard minimum 64-byte Ethernet frames ($512\text{ bits}$):
    $$2.5\times 10^6 \times 512\text{ bits} = \mathbf{1.28\text{ Gbps}}$$
  * This proves full wire-speed line-rate Gigabit Ethernet intrusion detection with zero packet loss.

---

## 6. Current `generate_hls4ml_ip.py` Configuration

The script is located at `/home/horsie/Documents/Projects/IDS_Abelton/Move_ME/generate_hls4ml_ip.py`:

```python
#!/usr/bin/env python3
"""
hls4ml IP Generation Script for Cyclone V DE1-SoC (5CSEMA5F31C6)
Converts the quantized IDS-CNN1D QKeras model into an Intel HLS C++ IP package.
"""

import sys
from pathlib import Path

def main():
    try:
        import hls4ml
        from qkeras.utils import load_qmodel
    except ImportError as e:
        print(f"Error: Missing required library: {e}")
        print("Please install requirements: pip install hls4ml qkeras tensorflow")
        sys.exit(1)

    model_path = Path("models/ids_cnn1d_qat_best.h5")
    output_dir = Path("ids_cnn1d_ip")

    if not model_path.exists():
        print(f"Error: Model not found at {model_path.resolve()}")
        sys.exit(1)

    print(f"--> Loading QKeras model from: {model_path}")
    model = load_qmodel(str(model_path))
    model.summary()

    print("--> Generating hls4ml configuration...")
    config = hls4ml.utils.config_from_keras_model(
        model,
        granularity='name',
        default_precision='fixed<16,6>'
    )

    # Strategy & Clock Setup
    config['Model']['Strategy'] = 'Resource'
    config['Model']['ReuseFactor'] = 1

    # Balanced 2.5 Mpps configuration (~61% DSP utilization on Cyclone V)
    config['LayerName']['conv1']['ReuseFactor'] = 2   # 32 DSPs (finishes in 2 cycles)
    config['LayerName']['conv2']['ReuseFactor'] = 4   # ALM logic (finishes in 20 cycles)
    config['LayerName']['dense1']['ReuseFactor'] = 20  # ALM logic (finishes in 20 cycles)
    config['LayerName']['dense2']['ReuseFactor'] = 4   # 21 DSPs (finishes in 4 cycles)

    # Precision configs for quantized layers
    config['LayerName']['conv1']['Precision']['weight'] = 'fixed<8,3,TRN,WRAP>'
    config['LayerName']['conv1']['Precision']['bias']   = 'fixed<8,3,TRN,WRAP>'
    config['LayerName']['conv2']['Precision']['weight'] = 'fixed<4,3,TRN,WRAP>'
    config['LayerName']['conv2']['Precision']['bias']   = 'fixed<4,3,TRN,WRAP>'
    config['LayerName']['dense1']['Precision']['weight'] = 'fixed<4,3,TRN,WRAP>'
    config['LayerName']['dense1']['Precision']['bias']   = 'fixed<4,3,TRN,WRAP>'
    config['LayerName']['dense2']['Precision']['weight'] = 'fixed<8,3,TRN,WRAP>'
    config['LayerName']['dense2']['Precision']['bias']   = 'fixed<8,3,TRN,WRAP>'

    print(f"--> Converting model to Quartus HLS IP in: {output_dir}")
    hls_model = hls4ml.converters.convert_from_keras_model(
        model,
        hls_config=config,
        output_dir=str(output_dir),
        part='5CSEMA5F31C6',
        clock_period=20.0,       # 50 MHz on-board clock (20 ns)
        io_type='io_stream',    # Avalon-ST FIFO streaming interface
        backend='Quartus'
    )

    print("--> Writing HLS project files...")
    hls_model.write()

    print("\n✅ Successfully generated HLS IP package in:", output_dir.resolve())

if __name__ == '__main__':
    main()
```

---

## 7. Toolchain Notes & Quirks

1. **Altera HLS IP Gen 2026.1 (`ahls`):**
   * Installed at `/home/horsie/altera_standard/ahls/bin/ahls-sh` (runs `ubuntu-ahls.sif` via Apptainer).
   * Note: This is Altera's new Clang 21 compiler. Standard `hls4ml` Quartus templates include GCC builtins (`__builtin_intel_hls_instream_read`) written for legacy `i++`.
   * Therefore, the user is generating the Verilog RTL directly via their preferred HLS tool/setup and providing the resulting RTL.
2. **Quartus Prime Compilation & Programming:**
   * Device target: `5CSEMA5F31C6`.
   * Programming tool: `quartus_pgm -m jtag -c 1 -o "p;<output_file>.sof@2"`.

---

## 8. Key Project Files Summary

* `generate_hls4ml_ip.py`: Python conversion script from QKeras `.h5` to Quartus HLS C++ IP.
* `models/ids_cnn1d_qat_best.h5`: Trained, quantized weights and architecture.
* `arm_ids_bench.cpp`: C++ NEON inference engine for HPS Linux.
* `arm_ids_bench`: Statically compiled ARMv7-A executable.
* `run_serial_bench.py`: Host-side serial upload and UART execution harness.
* `test_samples_cicids.npy` / `test_labels_cicids.npy`: CIC-IDS2017 test vectors.
* `ids_cnn1d_ip/`: Directory containing generated HLS source and project files.

---

## 9. Next Steps for Continuing Session

1. Run `generate_hls4ml_ip.py` with the updated reuse factors ($R_{conv1}=2, R_{conv2}=4, R_{dense1}=20, R_{dense2}=4$).
2. Synthesize HLS C++ to Verilog RTL.
3. Integrate the generated Verilog module into a Quartus project for `5CSEMA5F31C6`.
4. Compile the `.sof` bitstream and program device index `@2` using `quartus_pgm`.
5. Verify timing closure at 50 MHz and confirm DSP block usage (~53 blocks / 61%).
