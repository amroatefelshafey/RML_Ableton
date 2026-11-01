# fpga_ids_core: IDS-CNN1D-S on the DE1-SoC

Hand-written SystemVerilog for `models/ids_cnn1d_qat_best.h5`, bit-exact with
the QKeras model. There are two builds:

* **Standalone demo** (`de1_soc_ids_top`): 16 ROM samples, switches, KEYs,
  LEDs and HEX displays. No HPS.
* **HPS build** (`hps/`): the ARM writes features and reads the result over the
  HPS-to-FPGA bridge.

## Network and number formats

```
in (16x4 int8) -> conv1 3x4x16 + ReLU -> maxpool 2 -> conv2 3x16x24 + ReLU
               -> flatten 120 -> dense1 32 + ReLU -> dense2 8 -> argmax
```

| Tensor | QKeras / hls4ml type | Integer code |
|---|---|---|
| input | ap_fixed<8,4> | int8, value x16 |
| conv1, dense2 weights and bias | quantized_bits(8,2) | int8, value x32 |
| conv2, dense1 weights and bias | quantized_bits(4,2) | int4, value x2 |
| ReLU outputs | quantized_relu(6,2) = ufixed<6,2,RND_CONV,SAT> | uint6, value x16, round half to even, saturate at 63 |
| logits | dense2 accumulator | int21, value x512 |

Latency is 29 cycles, 0.58 us at 50 MHz: conv1 16 (14 positions + 2 pipeline
stages), pool 1, conv2 6 (5 + 1), dense1 2, dense2 3, argmax 1.

## Files

| File | Role |
|---|---|
| `ids_cnn1d_engine.sv` | The CNN. A state machine walks the layers, holding each layer's output in registers. conv1 and conv2 are pipelined, one output position per cycle; their windows and outputs move through shift registers, so no runtime-indexed muxes sit in the datapath. Every cycle does either multiplies/partial sums or the final sum and requant, never both, which is what lets it meet 50 MHz. Every weight index is a loop constant, so 4-bit weights become shifts and adds. |
| `ids_cnn1d_weights.sv` | Integer weights as packed-array `localparam`s, which Quartus Standard needs. Same values as `rtl/src/ids_cnn1d_weights_pkg.sv`, which is extracted from the model. |
| `de1_soc_ids_top.sv` | Standalone demo top. SW[3:0] picks a ROM sample and KEY[1] runs it; SW[9]=1 is free-run mode. LEDR[0] attack, LEDR[8:1] class, LEDR[9] busy. HEX0 class, HEX1 A/b, HEX3:2 latency, HEX4 sample, HEX5 0 = matches expected / F = mismatch. |
| `sample_rom.sv` | 16 labeled CIC-IDS2017 vectors (bench samples 0-15), already int8. |
| `hex_decoder.sv` | Active-low 7-segment decoder. |
| `de1_soc_ids_top.qsf/.qpf/.sdc` | Quartus project for the standalone demo. |
| `hps/ids_cnn1d_hps_avmm.sv` | Avalon-MM slave around the engine for the HPS-to-FPGA bridge (register map below). |
| `hps/ids_cnn1d_hps_avmm_hw.tcl` | Platform Designer component for it. |
| `hps/soc_system.tcl` | Builds `soc_system.qsys`: HPS + engine on the 32-bit HPS-to-FPGA bridge, IRQ on f2h_irq0. |
| `hps/de1_soc_ids_hps_top.sv` | HPS build top: DDR3 pins, LEDs and HEX from the result. |
| `hps/de1_soc_ids_hps.qsf/.qpf`, `hps/de1_soc_ids_hps_top.sdc` | Quartus project for the HPS build. |
| `hps/build_hps.sh` | Generates the system, compiles, writes `.sof` and `.rbf`, optionally programs the board. |
| `hps/ids_hps_client.c` | Linux userspace driver and self-test through `/dev/mem`. |
| `tb/` | Questa testbenches: engine vs 4,100 golden vectors, board top, HPS wrapper. `tb/run_sim.sh` runs them all. |

## Why the HPS-to-FPGA bridge

The DE1-SoC has three ways for the ARM to reach the FPGA:

| Path | Notes |
|---|---|
| Lightweight HPS-to-FPGA bridge (0xFF20_0000) | 32-bit only. On the HPS side it sits behind the L4 peripheral switch, so every read goes through an extra, slower switch. |
| **HPS-to-FPGA bridge (0xC000_0000)** | Hangs directly off the L3 main switch; 32/64/128-bit. Lowest read latency for the CPU. **Used here.** |
| FPGA-to-HPS / FPGA-to-SDRAM (FPGA is the master, DMA into DDR) | Highest throughput for streams of many results, but the ARM still reads DDR and has to deal with caching. For one 32-bit result per inference it is slower and much more work. |

The result path costs **one bridge read**: class, attack flag, valid, busy and
a sequence counter are packed into RESULT. The slave has no wait states and a
fixed read latency of 1, and the bridge is 32 bits wide to match, so
Platform Designer inserts no width adapter. Feature writes are posted. Writing
the last word starts the engine, so there's no separate START write.
Polling is faster than an interrupt here: the engine finishes in 0.58 us,
far less than Linux needs to wake a thread. The IRQ is wired up for drivers
that want it.

## HPS register map (word offsets, base 0xC000_0000 + component offset)

| Word | Byte | R/W | Register |
|---|---|---|---|
| 0 | 0x00 | R | RESULT: [2:0] class, [3] attack, [4] valid, [5] busy, [6] start pending, [15:8] latency, [31:16] SEQ |
| 1 | 0x04 | W | CTRL: [0] START, [1] AUTOSTART (default 1), [2] IRQ_EN |
| 2 | 0x08 | R/W1C | IRQ: [0] done pending |
| 3 | 0x0C | R | ID = 0x1D5C_0002 |
| 8-15 | 0x20 | R | LOGIT[0..7], signed, x512 |
| 16-31 | 0x40 | R/W | FEAT[0..15]: feature 4w in bits [7:0], same byte order as `int8_t x[64]` |

Driver loop (what `ids_classify()` in `ids_hps_client.c` does):

1. Read RESULT and note SEQ.
2. Write FEAT[0..15]. Writing FEAT[15] starts the engine.
3. Read RESULT until SEQ changes. Bits [2:0] are the class.

The engine copies FEAT when it starts, so once `pending` reads 0 the next
sample can be written while the current one computes. RESULT holds one
result, so read it before the next inference finishes.

## Verification status

| Check | Result |
|---|---|
| Engine vs 4,100 golden vectors (`rtl/data`, bit-exact with QKeras) | 0 logit / 0 class mismatches |
| Board top: 16 ROM samples + free-run | all match, latency 29 |
| HPS wrapper: autostart on all 4,100 vectors, queued start, IRQ, byte writes | 0 errors |
| Standalone demo, Quartus 25.1 Lite | fits: 13.7k ALMs (43%), 80/87 DSPs; timing met at all corners, Fmax 59.2 MHz |
| HPS build, Quartus 25.1 Lite | fits: 13.5k ALMs (42%), 80/87 DSPs; timing met on CLOCK_50 and the DDR3 clocks, all corners |
| On the board | **not yet run** |

The "No exact pin location" critical warnings in the HPS build are for the
DDR3 pins: they are dedicated HPS pins, and the fitter places them at their
fixed DE1-SoC locations in banks 6A/6B.

## Building and running

Simulation (Questa from Quartus Lite):

```bash
cd fpga_ids_core/tb && ./run_sim.sh
```

Standalone demo: open `de1_soc_ids_top.qpf` in Quartus Prime Lite and compile,
or run `quartus_sh --flow compile de1_soc_ids_top`.

HPS build, from Git Bash:

```bash
cd fpga_ids_core/hps && ./build_hps.sh
```

Use Quartus **Lite/Standard** (`C:/altera_lite/25.1std`). Quartus Pro does not
support Cyclone V; `build_hps.sh` ignores `QUARTUS_ROOTDIR` for that reason.

On the board (Linux on the HPS, as root):

1. Load the FPGA image. Either program `hps/output_files/de1_soc_ids_hps.sof`
   over JTAG (`./build_hps.sh --program`), or load the `.rbf` from U-Boot or
   Linux the way your image normally does.
2. Make sure the HPS-to-FPGA bridge is out of reset:
   `echo 1 > /sys/class/fpga_bridge/br0/enable` if your kernel has the
   fpga-bridge driver. Otherwise pass `-b` to the client.
3. Copy `hps/ids_hps_client.c` and `rtl/hps/ids_samples.h` to the board, then
   build and run:

```bash
gcc -O2 -o ids_hps_client ids_hps_client.c && ./ids_hps_client
```

It checks the FPGA is configured and the bridge is enabled before touching
the bridge, runs the 100 labeled samples, and compares every class and logit
against the golden values.

`soc_system.tcl` only configures the FPGA side of the HPS; the HPS
peripherals keep the setup your SD-card image's preloader gives them. If you
build a new preloader, start from Terasic's DE1_SoC_GHRD `soc_system.qsys`
and add `ids_cnn1d_hps_avmm` to it the same way (s0 on `h2f_axi_master` at
0x0, irq on `f2h_irq0`, clock and reset from `clk_0`).
