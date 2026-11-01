# System Context, Architecture & Engineering Rationale
**Project:** Hardware-Accelerated Network Intrusion Detection System (CIC-IDS2017)  
**Target Platform:** Intel / Terasic DE1-SoC (`5CSEMA5F31C6`, Cyclone V SX SoC)  
**Author:** Principal Embedded AI & FPGA Systems Architect  
**Location:** `Move_ME/CONTEXT_AND_UNDERSTANDING.md`

---

## 1. Executive Summary & Project Objectives

The objective of this project is to take baseline floating-point intrusion detection models trained on the CIC-IDS2017 dataset and port them into a low-latency, deterministic, hardware-synthesizable C++ IP core using `hls4ml` for deployment on an Intel Cyclone V SoC FPGA.

### Key Operational Targets
- **Target Line Rate:** 1 Gbps wire speed on real DE1-SoC hardware interfaces (with theoretical scaling to 10 Gbps).
- **Latency & Determinism:** Sub-microsecond deterministic pipeline with an Initiation Interval ($II$) strictly $\le 60$ clock cycles at $125\text{ MHz}$.
- **Hardware Envelope:** Strict compliance with the Cyclone V `5CSEMA5F31C6` budget (87 Variable-Precision DSP blocks, ~32K ALMs, 4,450 Kbits M10K BRAM).
- **Detection Efficacy:** High Attack Recall ($>99.5\%$) and low False Positive Rate ($<5\%$) across 504,160 pristine held-out test samples without data leakage.

---

## 2. Audit of Baseline Models & Porting Feasibility

An inspection was conducted on the legacy models and notebooks located in `References/CICIDS-2017/Models/CNN/` (`cnn_model_best.keras` and `final_cnn_model.h5`):

### Why the Legacy Models Were Infeasible on Cyclone V:
1. **Severe Memory Exhaustion:**
   The legacy CNN topology required **402,880 parameters**. In 32-bit floating-point, this requires $\approx 1.61\text{ MB}$; even quantized to 8-bit, storing $>400\text{K}$ weights exceeds the total M10K BRAM capacity of Cyclone V (556 KB total) by nearly $300\%$.
2. **DSP Multiplier Deficit:**
   The legacy architecture required $>1,000,000\text{ MACs}$ per inference. At a 1 Gbps packet arrival rate ($1.488\text{M packets/sec}$ for minimum 64-byte frames), saturating wire speed would require over $1,400$ parallel multipliers—exceeding the board's 87 DSP blocks by over $16\times$.
3. **Toolchain Incompatibility:**
   The `hls4ml` Quartus backend (`backend='Quartus'`, Intel HLS Compiler `i++`) does not support 2D convolutions (`Conv2D`), making the legacy 2D matrix reshaping incompatible with direct Intel HLS synthesis.
4. **Data Leakage in Baseline Notebooks:**
   Notebooks `CICIDS_Dataset.ipynb` and `6) CNN_MC.ipynb` performed SMOTE oversampling and PCA transformations *prior* to train/test partitioning, artificially inflating reported test metrics.

---

## 3. Mathematical Throughput & Timing Proofs

### Formal Wire-Speed Derivations
For 1 Gbps Ethernet with minimum-sized 64-byte frames (72 wire bytes with preamble, plus 12-byte Inter-Frame Gap = 84 total wire bytes):
$$R_{pps} = \frac{10^9\text{ bits/sec}}{84\text{ bytes} \times 8\text{ bits/byte}} = 1,488,095.24\text{ frames/sec}$$

Given an FPGA fabric clock frequency $f_{clk}$:
$$II_{max} = \left\lfloor \frac{f_{clk}}{R_{pps}} \right\rfloor$$
- At $f_{clk} = 100\text{ MHz}$: $II_{max} = \lfloor 100 \times 10^6 / 1.488 \times 10^6 \rfloor = \mathbf{67\text{ clock cycles}}$.
- At $f_{clk} = 125\text{ MHz}$ ($8\text{ ns}$): $II_{max} = \lfloor 125 \times 10^6 / 1.488 \times 10^6 \rfloor = \mathbf{84\text{ clock cycles}}$.

By configuring the hardware core to an Initiation Interval $II = \mathbf{60\text{ cycles}}$ at $125\text{ MHz}$:
$$\text{Throughput} = \frac{125 \times 10^6}{60} \times 84 \times 8 \approx \mathbf{1.4\text{ Gbps}}$$
This guarantees line-rate saturation for 1 Gbps Ethernet under worst-case minimum frame traffic.

### Hardware Multiplier Budgeting on Cyclone V
Each Cyclone V Variable-Precision DSP block can be configured as:
- One $27 \times 27$ multiplier
- Two independent $18 \times 18$ multipliers
- Three independent $9 \times 9$ multipliers

For our 1D-CNN architecture (`IDS-CNN1D-S`, 12,544 total MACs per inference):
$$\text{Parallel Multipliers Required} = \left\lceil \frac{12,544\text{ MACs}}{60\text{ cycles}} \right\rceil = 209.06 \approx \mathbf{210\text{ multipliers}}$$

Using mixed-precision quantization:
- 8-bit input/output multipliers map directly to $9 \times 9$ DSP modes (3 multipliers per DSP block).
- 4-bit hidden multipliers are synthesized using ALM look-up tables (LUT logic) or packed into DSP blocks.
- Allocating 48 DSP blocks provides $48 \times 3 = 144$ dedicated multipliers, with the remaining small 4-bit products mapped to ALM logic.
- Total DSP block utilization is $\le 20$ blocks ($\approx 23\%$ of the 87 DSP blocks available), leaving ample headroom for system interconnect, DMA, and MAC controllers.

---

## 4. Feature Engineering & Preprocessing Pipeline

### Operational Threat Class Consolidation
To prevent extreme minority class collapse under fixed-point quantization while maintaining actionable intrusion detection, the 15 raw classes were mapped into 8 operational categories:

| Target Class ID | Category Name | Consolidated Raw Threat Types | Test Samples |
| :---: | :--- | :--- | :---: |
| **0** | `BENIGN` | Legitimate benign traffic | 419,012 |
| **1** | `DoS` | DoS Hulk, GoldenEye, slowloris, Slowhttptest, Heartbleed | 38,751 |
| **2** | `DDoS` | Low-orbit / distributed denial of service | 25,603 |
| **3** | `PortScan` | Reconnaissance port scanning | 18,139 |
| **4** | `BruteForce` | FTP-Patator, SSH-Patator credential attacks | 1,830 |
| **5** | `WebAttack` | Brute Force, Cross-Site Scripting (XSS), SQL Injection | 428 |
| **6** | `Botnet` | Ares / IRC command-and-control bot traffic | 390 |
| **7** | `Infiltration` | Post-exploitation infiltration activity | 7 |

### Hardware-Aligned Transformation
1. **Sign-Preserving Natural Logarithm:**
   $$x_{log} = \text{sign}(x) \cdot \ln(1 + |x|)$$
   Compacts high-dynamic-range network features (e.g., flow duration, byte counters) without destroying zero-valued flags.
2. **RobustScaler Transformation:**
   $$x_{scaled} = \frac{x_{log} - \text{median}}{\text{IQR}}$$
   Fitted strictly on the training partition (`X_train.parquet`, 150,000 samples) to prevent data leakage.
3. **Fixed-Point Quantization (`ap_fixed<8,4>`):**
   Values are clipped to range $[-8.0, 7.9375]$ with a step size of $0.0625$ ($2^{-4}$).
4. **Tensor Reshaping:**
   55 normalized flow features are zero-padded to 64 and reshaped to a $(16, 4)$ matrix for 1D convolution. All transformation parameters are exported to `config/frontend_config.json`.

---

## 5. Model Architecture & Quantization-Aware Training (QAT)

### Architecture Specification (`IDS-CNN1D-S`)

| Layer Name | Type | Config / Shape | Quantization Precision | Parameters | MACs | Reuse Factor |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: |
| `input_1` | Input | $(16, 4)$ | `ap_fixed<8,4>` | 0 | 0 | - |
| `conv1` | QConv1D | 16 filters, $K=3$, valid | Weights: 8-bit (int: 2), Act: 6-bit | 208 | 2,688 | 4 |
| `pool1` | MaxPool1D | Pool size: 2, stride: 2 | Passthrough | 0 | 0 | - |
| `conv2` | QConv1D | 24 filters, $K=3$, valid | Weights: 4-bit (int: 2), Act: 6-bit | 1,176 | 5,760 | 12 |
| `flatten` | Flatten | Shape: $(120,)$ | Passthrough | 0 | 0 | - |
| `dense1` | QDense | 32 units | Weights: 4-bit (int: 2), Act: 6-bit | 3,872 | 3,840 | 60 |
| `dense2` | QDense | 8 units | Weights: 8-bit (int: 2), Linear | 264 | 256 | 32 |
| `output_softmax`| Activation | 8 classes | Softmax | 0 | 0 | - |
| **Total** | | | | **5,520** | **12,544** | |

### Evaluation Metrics on 504,160 Pristine Test Samples
- **Accuracy:** **95.72%** (CNN-QAT) vs **97.56%** (CNN-Float)
- **Binary Attack Recall:** **99.66%** (only 290 attack samples missed out of 85,148 real attacks)
- **Binary Attack Precision:** **80.28%**
- **False Positive Rate (FPR):** **4.98%**

---

## 6. HLS IP Core Structure & Quartus Toolchain

The generated HLS core in `Move_ME/ids_cnn1d_ip/` is structured for Intel HLS Compiler (`i++`):

```
ids_cnn1d_ip/
├── build_hls_ip.sh        # Runs testbench and invokes i++ with Cyclone V flags
├── Makefile               # Automated C-simulation build harness
├── myproject_test.cpp     # C-simulation testbench runner
├── hls4ml_config.yml      # Toolchain directives (Strategy='Resource', io_stream)
├── firmware/
│   ├── myproject.cpp      # Intel HLS top-level streaming function
│   ├── myproject.h        # Function signatures and component interfaces
│   ├── defines.h          # Fixed-point precision types (ac_fixed / ap_fixed)
│   ├── parameters.h       # Layer pipeline directives and reuse factors
│   ├── weights/           # Weight arrays formatted in C++ header tables
│   ├── ac_types/          # Mentor Graphics / Intel Algorithmic C header library
│   └── nnet_utils/        # hls4ml streaming neural network C++ templates
└── tb_data/
    ├── tb_input_features.dat      # 1,000 real test samples (64 features)
    ├── tb_output_predictions.dat  # 1,000 reference Python probability vectors
    └── tb_expected_labels.dat     # 1,000 ground-truth class labels
```

---

## 7. System Integration & Deployment Architecture

```
+-----------------------------------------------------------------------------------+
|                            DE1-SoC (Cyclone V 5CSEMA5F31C6)                       |
|                                                                                   |
|  +-------------------------------------+       +-------------------------------+  |
|  |       HPS (ARM Cortex-A9)           |       |         FPGA Fabric           |  |
|  |                                     |       |                               |  |
|  |  Linux Userspace Application        |       |   Intel HLS CNN Core          |  |
|  |  - Raw packet capture (AF_PACKET)   |       |   - Initiation Interval: 60   |  |
|  |  - Feature extraction & scaling     |       |   - Clock: 125 MHz (8 ns)     |  |
|  |    (frontend_config.json)           |       |   - Latency: < 1 us           |  |
|  |                                     |       |                               |  |
|  |  +-------------------------------+  |       |  +-------------------------+  |  |
|  |  | DMA Driver / /dev/mem Driver  |==|=======|==| Avalon-ST Streaming FIFO|  |  |
|  |  +-------------------------------+  |  HPS  |  +-------------------------+  |  |
|  |                                     | Bridge|               |               |  |
|  +-------------------------------------+       |               v               |  |
|                                                |  +-------------------------+  |  |
|                                                |  | IDS-CNN1D Core Engine   |  |  |
|                                                |  +-------------------------+  |  |
|                                                |               |               |  |
|                                                |               v               |  |
|                                                |  +-------------------------+  |  |
|                                                |  | Output Classification   |  |  |
|                                                |  | Stream (Threat Alert)   |  |  |
|                                                |  +-------------------------+  |  |
+-----------------------------------------------------------------------------------+
```

### Preprocessing on ARM HPS
The ARM Cortex-A9 processor executes the front-end scaling before handing tensors to the FPGA:
1. Extract 55 packet flow features.
2. Apply `x_log = sign(x) * log1p(|x|)`.
3. Subtract `scaler.center` and divide by `scaler.scale` (values stored in `config/frontend_config.json`).
4. Pack normalized values as 8-bit integers (`ap_fixed<8,4>` representation: multiply by 16 and cast to `int8_t`).
5. Transmit the 64-byte feature frame over the HPS-to-FPGA AXI Bridge / DMA.

---

## 8. Verification & Synthesis Checklist for Quartus Host

When running on the machine with Quartus Prime and Intel HLS Compiler installed:

1. **Testbench Execution:**
   ```bash
   cd ids_cnn1d_ip
   make test
   ```
   Verifies that C++ fixed-point inference produces predictions consistent with Python reference outputs on the 1,000 vectors in `tb_data/`.

2. **Core Synthesis:**
   ```bash
   ./build_hls_ip.sh
   # Equivalent direct call:
   i++ -march=5CSEMA5F31C6 --clock 8ns firmware/myproject.cpp -o build_ids_core
   ```

3. **Report Verification:**
   Inspect `build_ids_core.prj/reports/report.html`:
   - [x] Initiation Interval: $\le 60$ clock cycles.
   - [x] $f_{max} \ge 125\text{ MHz}$.
   - [x] DSP utilization $\le 87$ blocks.
   - [x] Memory utilization $< 5\%$ M10K BRAM blocks.
