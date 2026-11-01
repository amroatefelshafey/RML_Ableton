#!/usr/bin/env python3
"""
hls4ml IP Generation Script for Cyclone V DE1-SoC (5CSEMA5F31C6)
Converts the quantized IDS-CNN1D QKeras model into an Intel HLS C++ IP package.
"""

import re
import sys
from pathlib import Path


def patch_for_ahls(output_dir):
    """hls4ml 1.3 emits oneAPI code for the Intel-branded compiler. The Altera
    HLS 2026 (ahls, Clang 21) toolchain renamed the SYCL FPGA extensions from
    sycl::ext::intel / <sycl/ext/intel/...> to sycl::ext::altera. It also does
    not define __INTEL_CLANG_COMPILER, so the generated "#if (version < 2025)"
    check would pull in a prototype header that no longer exists."""
    rules = [
        (re.compile(r"sycl/ext/intel/"), "sycl/ext/altera/"),
        (re.compile(r"sycl::ext::intel::"), "sycl::ext::altera::"),
        (re.compile(r"#if \(__INTEL_CLANG_COMPILER < (\d+)\)"),
         r"#if defined(__INTEL_CLANG_COMPILER) && (__INTEL_CLANG_COMPILER < \1)"),
    ]
    for path in sorted((output_dir / "src").rglob("*")):
        if path.suffix not in (".h", ".hpp", ".cpp"):
            continue
        text = path.read_text()
        new = text
        for pat, rep in rules:
            new = pat.sub(rep, new)
        if new != text:
            path.write_text(new)
            print(f"    patched {path.relative_to(output_dir)}")

    # hls4ml bug: with the Resource strategy the oneAPI backend pads dense
    # weights to reuse_factor_rounded * block_factor_rounded (powers of two)
    # and the kernel indexes the padded array, but defines.h still declares
    # the unpadded n_in*n_out size. Size each wN_t to the values actually written.
    defines = output_dir / "src" / "firmware" / "defines.h"
    dtext = defines.read_text()
    for wfile in sorted((output_dir / "src" / "firmware" / "weights").glob("w*.h")):
        wtext = wfile.read_text()
        body = wtext[wtext.index("{{") + 2:wtext.rindex("}}")]
        count = len([v for v in body.split(",") if v.strip()])
        pat = re.compile(rf"(typedef nnet::array<[^;]*?,\s*)([^>;]+)(>\s*{wfile.stem}_t;)")
        m = pat.search(dtext)
        declared = m and re.fullmatch(r"[\d\s*]+", m.group(2)) and \
            eval(m.group(2))     # e.g. "3840*1"; digits and '*' only
        if m and declared != count:
            print(f"    {wfile.stem}_t: {m.group(2).strip()} -> {count} elements")
            dtext = pat.sub(lambda mm: f"{mm.group(1)}{count}{mm.group(3)}", dtext)
    defines.write_text(dtext)

    # hls4ml puts any weight array >= 2048 elements (here only dense1, 8192
    # after padding) in BLOCK_RAM with numbanks = size/2 = 4096 banks, which
    # ahls constant-folds ("w8 has memory attributes but no uses") before the
    # link step runs out of memory. Store it as register constants like the
    # other three layers' weights. (BramFactor cannot change this: the oneAPI
    # backend rejects it with "Weights on the interface is not supported".)
    bram_attr = re.compile(r"\[\[intel::bankwidth\([^]]*fpga_memory\(\"BLOCK_RAM\"\)\]\]")
    for wfile in sorted((output_dir / "src" / "firmware" / "weights").glob("w*.h")):
        wtext = wfile.read_text()
        if bram_attr.search(wtext):
            wfile.write_text(bram_attr.sub("[[intel::fpga_register]]", wtext))
            print(f"    {wfile.stem}: BLOCK_RAM banks -> fpga_register")


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

    # Global optimization strategy for Cyclone V DSP / ALM budget
    config['Model']['Strategy'] = 'Resource'
    config['Model']['ReuseFactor'] = 1

    # Layer-specific reuse factors for balanced 2.5 Mpps (II <= 20 cycles @ 50 MHz, ~61% DSPs)
    config['LayerName']['conv1']['ReuseFactor'] = 2   # 32 DSP blocks (finishes in 2 cycles)
    config['LayerName']['conv2']['ReuseFactor'] = 4   # ALM logic (finishes in 20 cycles)
    config['LayerName']['dense1']['ReuseFactor'] = 20  # ALM logic (finishes in 20 cycles)
    config['LayerName']['dense2']['ReuseFactor'] = 4   # 21 DSP blocks (finishes in 4 cycles)

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
        clock_period=20.0,       # 50 MHz on-board oscillator (20.0 ns)
        io_type='io_stream',    # Avalon-ST FIFO streaming interface
        backend='oneAPI'
    )

    print("--> Writing HLS project files...")
    hls_model.write()

    print("--> Patching generated sources for Altera HLS 2026 (ahls)...")
    patch_for_ahls(output_dir)

    print("\n✅ Successfully generated HLS IP package in:", output_dir.resolve())
    print("Next step: Run HLS synthesis (`i++` or `./build_hls_ip.sh`) in that directory to produce Verilog RTL.")

if __name__ == '__main__':
    main()
