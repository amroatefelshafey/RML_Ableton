#!/usr/bin/env bash
# ==============================================================================
# Automated Altera HLS 2026.1 Verilog RTL & IP Synthesis Script
# Target: Intel Cyclone V SoC (5CSEMA5F31C6) @ 50 MHz (20.0 ns)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HLS_DIR="${SCRIPT_DIR}/ids_cnn1d_ip"

if [ ! -d "${HLS_DIR}" ]; then
    if [ -f "${SCRIPT_DIR}/src/firmware/myproject.cpp" ]; then
        HLS_DIR="${SCRIPT_DIR}"
    else
        echo "[-] Error: Cannot find ids_cnn1d_ip directory."
        exit 1
    fi
fi

# Locate ahls-sh runner
AHLS_SH=""
CANDIDATES=(
    "${AHLS_SH:-}"
    "${HOME}/altera_standard/ahls/bin/ahls-sh"
    "/home/horsie/altera_standard/ahls/bin/ahls-sh"
    "/home/u23200267/altera_standard/ahls/bin/ahls-sh"
    "$(which ahls-sh 2>/dev/null || true)"
)

for c in "${CANDIDATES[@]}"; do
    if [ -n "$c" ] && [ -x "$c" ]; then
        AHLS_SH="$c"
        break
    fi
done

if [ -z "${AHLS_SH}" ]; then
    echo "[-] Error: ahls-sh compiler runner not found!"
    echo "    Please set AHLS_SH=/path/to/altera_standard/ahls/bin/ahls-sh"
    exit 1
fi

echo "[+] Using Altera HLS compiler runner: ${AHLS_SH}"
echo "[+] Target FPGA: Cyclone V 5CSEMA5F31C6 @ 50 MHz (20.0 ns)"
echo "[+] Working directory: ${HLS_DIR}"

cd "${HLS_DIR}"

# Step 1: Compile host test/wrapper code (contains sycl::queue & single_task kernel submission)
echo "------------------------------------------------------------------------"
echo "[+] Step 1/3: Compiling src/firmware/myproject.cpp -> myproject.o ..."
"${AHLS_SH}" ahls \
    -fsycl -fintelfpga -qactypes -c -Wno-unused-label \
    -fconstexpr-steps=134217728 \
    -Isrc/firmware \
    src/firmware/myproject.cpp -o myproject.o

echo "[+] Step 2/3: Compiling src/myproject_test.cpp -> myproject_test.o ..."
"${AHLS_SH}" ahls \
    -fsycl -fintelfpga -qactypes -c -Wno-unused-label \
    -fconstexpr-steps=134217728 \
    -Isrc/firmware \
    src/myproject_test.cpp -o myproject_test.o

# Step 2: Early link hardware synthesis
echo "------------------------------------------------------------------------"
echo "[+] Step 3/3: Running HLS Early-Link Synthesis (Verilog RTL Generation) ..."
echo "[+] (This synthesizes the scheduled RTL without full Quartus place-and-route)"
"${AHLS_SH}" ahls \
    -fsycl -fintelfpga -qactypes -Wno-unused-label \
    -fconstexpr-steps=134217728 \
    -v \
    -Xsv \
    -Xsreport \
    -Xshardware \
    -Xstarget=5CSEMA5F31C6 \
    -Xsclock=20.0ns \
    -Xsoptimize=latency \
    -fsycl-link=early \
    myproject.o myproject_test.o \
    -o ids_cnn1d_ip.a

echo "========================================================================"
echo "[+] HLS Synthesis Completed Successfully!"
echo "========================================================================"

# Step 3: Hardware Report & Metric Parser
python3 - << 'EOF'
import os
import json
import re
from pathlib import Path

prj_dir = Path("ids_cnn1d_ip.prj")
if not prj_dir.exists():
    # Check alternate project dir
    candidates = list(Path(".").glob("*.prj"))
    if candidates:
        prj_dir = candidates[0]

report_js = prj_dir / "reports" / "resources" / "report_data.js"
if not report_js.exists():
    print(f"[-] Warning: Report data not found at {report_js}")
    exit(0)

print(f"\n[+] Parsing Hardware Utilization from: {report_js}\n")
content = report_js.read_text(encoding="utf-8", errors="ignore")

def extract_json(var_name):
    pattern = rf"(?:var|let|const)\s+{var_name}\s*=\s*(\{{.*?\}});|(\[.*?\]);"
    m = re.search(rf"(?:var|let|const)\s+{var_name}\s*=\s*", content)
    if not m:
        return None
    start = m.end()
    # Find matching brace
    first_char = content[start]
    close_char = '}' if first_char == '{' else ']' if first_char == '[' else None
    if not close_char:
        return None
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(content)):
        c = content[i]
        if escape:
            escape = False
            continue
        if c == '\\':
            escape = True
            continue
        if c == '"' and not escape:
            in_string = not in_string
            continue
        if not in_string:
            if c == first_char:
                depth += 1
            elif c == close_char:
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(content[start:i+1])
                    except Exception:
                        return None
    return None

summary = extract_json("summaryJSON")
area = extract_json("areaJSON")
loops = extract_json("loopsJSON")

print("=" * 70)
print(f"{'RESOURCE UTILIZATION SUMMARY (5CSEMA5F31C6 @ 50 MHz)':^70}")
print("=" * 70)

if summary and "summary" in summary:
    for item in summary.get("summary", []):
        name = item.get("name", "")
        est = item.get("estimate", item.get("total", ""))
        avail = item.get("available", "")
        pct = item.get("percent", "")
        if name:
            print(f"  * {name:<30}: {str(est):>10} / {str(avail):<8} ({pct}%)")
elif area:
    print(f"  Area model data extracted from areaJSON.")

print("-" * 70)
print(f"{'LOOP INITIATION INTERVALS (II) & LATENCY':^70}")
print("-" * 70)

if loops and "children" in loops:
    def print_loops(node, indent=2):
        name = node.get("name", "")
        ii = node.get("ii", "N/A")
        lat = node.get("latency", "N/A")
        pipelined = node.get("pipelined", "")
        if name:
            info = f"II={ii}, Latency={lat}"
            if pipelined:
                info += f", Pipelined={pipelined}"
            print(f"{' '*indent}* {name:<32}: {info}")
        for child in node.get("children", []):
            print_loops(child, indent + 2)
    print_loops(loops)

print("=" * 70)

# Check Verilog and Qsys files
verilog_files = list(prj_dir.glob("**/*.v")) + list(prj_dir.glob("**/*.sv"))
hw_tcl_files = list(prj_dir.glob("**/*_hw.tcl"))

print("\n[+] Generated Top-Level Verilog & Platform Designer Artifacts:")
if hw_tcl_files:
    for f in hw_tcl_files:
        print(f"  * Qsys IP Component : {f.resolve()}")
if verilog_files:
    top_v = [f for f in verilog_files if "ids_cnn1d_ip" in f.name]
    if top_v:
        print(f"  * Top-level RTL     : {top_v[0].resolve()}")
    print(f"  * Total HDL Modules : {len(verilog_files)} SystemVerilog/Verilog files in {prj_dir}/")

print("\n[+] Done.")
EOF
