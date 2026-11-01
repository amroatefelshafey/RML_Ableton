# IDS-CNN1D-S in hand-written SystemVerilog

A synthesizable RTL implementation of `models/ids_cnn1d_qat_best.h5` for the
DE1-SoC (Cyclone V 5CSEMA5F31C6). It replaces the hls4ml → Altera HLS flow and
is **bit-exact** with the QKeras model.

## Why not the HLS flow

* `ids_cnn1d_ip.prj/logs/ids_cnn1d_ip.log` ends in `Killed`: the HLS compiler
  (`aoc`) ran out of memory on this 7 GB machine, leaving `ids_cnn1d_ip.v` empty.
* `ids_cnn1d_early.prj` reports `No kernels specified`: it was linked without
  the testbench object that submits the kernel.
* `hls4ml_config.yml` says `Backend: oneAPI`, and that is being fed through the
  2026 `ahls` (Clang 21) toolchain that hls4ml does not target. Even with more
  RAM, getting usable RTL out of that combination is not guaranteed.

The old hand-written attempt in `../fpga_ids_core/` failed Quartus analysis
(`automatic` declared after statements). It also did 8×120 and 24×48 MACs in
one cycle, which would not fit or meet timing. Its shifts were never checked
against the model.

## Verified results (Questa simulation)

| Check | Result |
|---|---|
| Integer reference vs QKeras logits, 4 100 vectors | 0 mismatches (exact) |
| RTL vs reference, all 8 logits + class, 4 100 vectors | 0 mismatches, with and without random backpressure |
| Accuracy, 100 labeled CIC-IDS2017 samples | 97 % (same as the ARM baseline) |
| Throughput | 1 sample / 15 cycles → **3.33 M inferences/s @ 50 MHz** |
| Latency | 24 cycles = **0.48 µs** @ 50 MHz |
| Board top (bench + single mode) and Avalon-MM wrapper | pass |

The ARM baseline was 321 µs/sample (~3 100/s).

**Resource estimate (Yosys `synth_intel_alm -family cyclonev`, engine only).**
This is not a Quartus fit. It produced about 26 k LUTs plus 6.5 k arithmetic
cells, with 3.1 k flip-flops, against 64 k ALUTs (32 k ALMs) on the device. It
also used 200 9×9 multipliers (≈67 of the 87 DSP blocks), which Yosys picked
for the 8-bit constant multiplies in conv1 and dense2. Expect Quartus to land
nearer 50 % of the device. Check fit and timing once Quartus is working.

## Architecture

All weights are hard-wired constants. Zero weights disappear and the 4-bit
layers (weights only in {-1, -0.5, 0, 0.5, 1}) reduce to shifts and adder
trees, so they use no multipliers.

```
in(64×int8) → S1 conv1+ReLU+pool → S2 conv2+ReLU → S3 dense1+ReLU → S4 dense2 → S5 argmax
              1 position/cycle      1 position/cycle  1 cycle          1 cycle     1 cycle
              14 cycles             5 cycles
```

Stages hand off through valid/ready registers, so up to five samples are in
flight at once.

| Tensor | Format | Integer code |
|---|---|---|
| input | ap_fixed<8,4> | int8, value×16 |
| conv1 / dense2 weights, bias | quantized_bits(8,2) | int8, value×32 |
| conv2 / dense1 weights, bias | quantized_bits(4,2) | int4, value×2 |
| ReLU outputs | quantized_relu(6,2) | uint6, value×16, round-half-even, saturate |

## Files

```
rtl/
├── scripts/gen_rtl_data.py     model → weights package, test vectors, ROMs, C header
├── scripts/run_sim.sh          Questa: `engine` or `system` testbench
├── scripts/build_fpga.sh       Quartus compile (+ --program)
├── src/ids_cnn1d_weights_pkg.sv  (generated) weights + accumulator widths
├── src/adder_tree.sv           balanced adder tree
├── src/ids_cnn1d_engine.sv     the inference engine
├── src/ids_cnn1d_avmm.sv       Avalon-MM slave wrapper for the HPS LW bridge
├── src/de1_soc_ids_top.sv      standalone board demo (switches / HEX / LEDs)
├── src/hex_decoder.sv
├── tb/tb_ids_cnn1d_engine.sv   bit-exact engine testbench
├── tb/tb_system.sv             board-top and Avalon wrapper testbench
├── ids_cnn1d_avmm_hw.tcl       Platform Designer component
├── hps/ids_fpga_test.c         ARM-side test via /dev/mem (+ generated ids_samples.h)
├── quartus/                    DE1-SoC project (.qpf/.qsf/.sdc)
└── data/                       (generated) test vectors and ROM images
```

## Usage

```bash
# 1. Regenerate everything from the model (re-run after retraining)
.venv/bin/python rtl/scripts/gen_rtl_data.py

# 2. Simulate
rtl/scripts/run_sim.sh engine            # 4100 vectors, bit-exact check
rtl/scripts/run_sim.sh engine +STRESS=1  # with random stalls
rtl/scripts/run_sim.sh system            # board top + Avalon wrapper

# 3. Build and program the standalone demo (needs a working Quartus, see below)
QUARTUS_BIN=/path/to/quartus/bin rtl/scripts/build_fpga.sh --program
```

### Board demo (`de1_soc_ids_top`)

* `KEY[0]` reset.
* `SW[9]=0`: `SW[6:0]` selects one of the 100 samples and `KEY[1]` classifies it.
  HEX0 shows the class, HEX1 shows `A` (attack) or `b` (benign), HEX2 the true
  label, HEX3 the Python-reference class, HEX5:4 the sample index.
* `SW[9]=1`: streams all 100 samples at full rate. HEX1:0 shows correct
  answers per pass (**97**), HEX3:2 the measured cycles per sample (**0F**), and
  HEX5:4 the mismatches against the reference (**00**).

### HPS integration

1. Start from the DE1-SoC Golden Hardware Reference Design (Terasic CD).
2. Add `rtl/` to Platform Designer's IP search path and add
   "IDS-CNN1D Accelerator". Connect `s0` to `hps_0.h2f_lw_axi_master`, and
   connect the clock and reset.
3. Generate, compile, and boot Linux. Then on the board:
   `./ids_fpga_test <offset>`. Cross-compile it with
   `arm-none-linux-gnueabihf-gcc -O2 -static rtl/hps/ids_fpga_test.c -o ids_fpga_test`.

The register map is documented at the top of `src/ids_cnn1d_avmm.sv`. Per-sample
time over the LW bridge will be dominated by the ~26 MMIO accesses, not the
0.48 µs engine latency. For line rate, feed the engine from a DMA or FIFO
instead.

## Quartus licence note

The Quartus Prime **Standard** install in `~/altera_standard` stopped on
2026-10-28 with *"Your 30-day evaluation period has expired"*. Quartus Prime
**Lite** 25.1 is free, supports the 5CSEMA5F31C6, and compiles this project
unchanged. The earlier Lite install in `~/altera_lite` has been removed.
