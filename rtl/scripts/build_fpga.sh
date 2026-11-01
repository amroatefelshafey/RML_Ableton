#!/usr/bin/env bash
# Compile the DE1-SoC standalone demo and (optionally) program the board.
# Needs Quartus Prime Lite or Standard (with a valid license) on PATH, or
# QUARTUS_BIN pointing at its bin/ directory.
# Usage: rtl/scripts/build_fpga.sh [--program]
set -euo pipefail
cd "$(dirname "$0")/../quartus"
[ -n "${QUARTUS_BIN:-}" ] && export PATH="$QUARTUS_BIN:$PATH"
quartus_sh --flow compile de1_soc_ids_top
echo "---- resources ----"
grep -E "Logic utilization|Total registers|Total block memory|DSP" output_files/de1_soc_ids_top.fit.summary || true
echo "---- timing (slow 85C model) ----"
grep -A3 "Slow 1100mV 85C Model Fmax Summary" output_files/de1_soc_ids_top.sta.rpt | tail -2 || true
grep -E "^; (Setup|Hold).*CLOCK_50" output_files/de1_soc_ids_top.sta.rpt | head -4 || true
if [ "${1:-}" = "--program" ]; then
    # Device 2 on the DE1-SoC JTAG chain is the FPGA (device 1 is the HPS)
    quartus_pgm -m jtag -c 1 -o "p;output_files/de1_soc_ids_top.sof@2"
fi
