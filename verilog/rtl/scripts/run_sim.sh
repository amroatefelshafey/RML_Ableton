#!/usr/bin/env bash
# Compile and run a testbench in Questa (Altera Starter Edition).
# Usage: rtl/scripts/run_sim.sh [engine|system] [vsim plusargs, e.g. +STRESS=1]
set -euo pipefail
cd "$(dirname "$0")/.."
QUESTA="${QUESTA:-$HOME/altera_standard/25.1std/questa_fse/bin}"
TB="${1:-engine}"; shift || true
case "$TB" in
    engine) TOP=tb_ids_cnn1d_engine ;;
    system) TOP=tb_system ;;
    *) echo "unknown testbench '$TB' (engine|system)"; exit 1 ;;
esac
mkdir -p sim && cd sim
ln -sfn ../data data
"$QUESTA/vlib" work >/dev/null
"$QUESTA/vlog" -sv -quiet ../src/ids_cnn1d_weights_pkg.sv ../src/adder_tree.sv \
    ../src/ids_cnn1d_engine.sv ../src/hex_decoder.sv ../src/de1_soc_ids_top.sv \
    ../src/ids_cnn1d_avmm.sv ../tb/tb_ids_cnn1d_engine.sv ../tb/tb_system.sv
"$QUESTA/vsim" -c -quiet "$TOP" "$@" -do "run -all; quit -f"
