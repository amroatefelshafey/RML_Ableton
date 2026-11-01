#!/usr/bin/env bash
# Build the DE1-SoC HPS + IDS-CNN1D FPGA image.
#   ./build_hps.sh            generate the system, compile, write .sof and .rbf
#   ./build_hps.sh --program  also program the board over USB-Blaster (JTAG)
# Run from fpga_ids_core/hps in Git Bash. Uses Quartus Prime Lite/Standard from
# QUARTUS_STD_ROOT (default C:/altera_lite/25.1std/quartus).
set -euo pipefail
cd "$(dirname "$0")"

# Cyclone V needs Quartus Prime Lite/Standard. QUARTUS_ROOTDIR on this machine
# points at a Quartus Pro install, so it is not used here.
QROOT="${QUARTUS_STD_ROOT:-/c/altera_lite/25.1std/quartus}"
command -v cygpath >/dev/null && QROOT="$(cygpath -u "$QROOT")"
export QUARTUS_ROOTDIR="$(cygpath -w "$QROOT" 2>/dev/null || echo "$QROOT")"
export PATH="$QROOT/bin64:$QROOT/sopc_builder/bin:$PATH"
HERE="$(pwd -W 2>/dev/null || pwd)"
REV=de1_soc_ids_hps

[ -f soc_system.qsys ] || qsys-script --script=soc_system.tcl --search-path="$HERE,\$"
qsys-generate soc_system.qsys --synthesis=VERILOG --search-path="$HERE,\$" --part=5CSEMA5F31C6

quartus_map  "$REV"
# Run it under quartus_sta directly: launched from quartus_sh it re-execs
# itself, and Tcl exec fails on the harmless TBBmalloc note Quartus prints
# on stderr on Windows.
quartus_sta  -t soc_system/synthesis/submodules/hps_sdram_p0_pin_assignments.tcl "$REV"
quartus_fit  "$REV"
quartus_sta  "$REV"
quartus_asm  "$REV"

# Compressed raw binary for loading from Linux or U-Boot
quartus_cpf -c -o bitstream_compression=on "output_files/$REV.sof" "output_files/$REV.rbf"

if [ "${1:-}" = "--program" ]; then
    # Device 2 on the DE1-SoC JTAG chain is the FPGA (device 1 is the HPS)
    quartus_pgm -m jtag -o "p;output_files/$REV.sof@2"
fi
echo "Done: output_files/$REV.sof, output_files/$REV.rbf"
