#!/usr/bin/env python3
"""
Extract integer weights from the QKeras model, build a pure-integer reference
model of IDS-CNN1D-S, prove it is bit-exact against QKeras, and emit:

  rtl/src/ids_cnn1d_weights_pkg.sv   SystemVerilog package with integer weights
  rtl/data/tb_inputs.hex             test inputs, one sample per line (64 x int8)
  rtl/data/tb_expected.hex           expected dense2 logits + argmax per sample
  rtl/data/tb_labels.txt             ground-truth labels (first 100 samples only)

Fixed-point formats (all derived from the model's quantizers):
  input            ap_fixed<8,4>      int8   scale 16
  conv1/dense2 W,b quantized_bits(8,2) int8   scale 32
  conv2/dense1 W,b quantized_bits(4,2) int4   scale 2
  relu outputs     quantized_relu(6,2) uint6  scale 16, round-half-even, sat 63

Usage (from Move_ME/):  .venv/bin/python rtl/scripts/gen_rtl_data.py [--random N]
"""
import argparse
import os
import re
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import numpy as np

ROOT = Path(__file__).resolve().parents[2]          # Move_ME/
RTL = ROOT / "rtl"

# (layer name, weight scale) -> integer code = value * scale
LAYER_SCALES = {"conv1": 32, "conv2": 2, "dense1": 2, "dense2": 32}


# ----------------------------------------------------------------------------
# Integer reference model (this is exactly what the RTL computes)
# ----------------------------------------------------------------------------
def rhe_shift(acc, sh):
    """Round-half-to-even of acc / 2**sh (matches tf.round in quantized_relu)."""
    acc = np.asarray(acc, dtype=np.int64)
    q = acc >> sh                       # floor
    rem = acc - (q << sh)
    half = 1 << (sh - 1)
    up = (rem > half) | ((rem == half) & ((q & 1) == 1))
    return q + up


def relu6(acc, sh):
    return np.clip(rhe_shift(acc, sh), 0, 63)


def int_forward(x, W):
    """x: (N,16,4) int8 codes. Returns (logits int (N,8) at scale 512, intermediates)."""
    x = x.astype(np.int64)
    N = x.shape[0]
    # conv1: acc scale 16*32 = 512, bias scale 32 -> <<4
    w1, b1 = W["conv1"]                       # (3,4,16), (16,)
    a1 = np.zeros((N, 14, 16), np.int64)
    for t in range(14):
        a1[:, t, :] = np.einsum("nkc,kcf->nf", x[:, t:t + 3, :], w1) + (b1 << 4)
    h1 = relu6(a1, 5)                         # 512 -> 16
    p1 = np.maximum(h1[:, 0::2, :], h1[:, 1::2, :])   # (N,7,16)
    # conv2: acc scale 16*2 = 32, bias scale 2 -> <<4
    w2, b2 = W["conv2"]                       # (3,16,24)
    a2 = np.zeros((N, 5, 24), np.int64)
    for t in range(5):
        a2[:, t, :] = np.einsum("nkc,kcf->nf", p1[:, t:t + 3, :], w2) + (b2 << 4)
    h2 = relu6(a2, 1)                         # 32 -> 16
    fl = h2.reshape(N, 120)                   # Keras Flatten: index = t*24 + c
    w3, b3 = W["dense1"]                      # (120,32)
    a3 = fl @ w3 + (b3 << 4)
    h3 = relu6(a3, 1)
    w4, b4 = W["dense2"]                      # (32,8)
    logits = h3 @ w4 + (b4 << 4)              # scale 512
    pred = np.argmax(logits, axis=1)          # first max wins, same as RTL
    return logits, pred, dict(a1=a1, h1=h1, p1=p1, a2=a2, h2=h2, a3=a3, h3=h3)


# ----------------------------------------------------------------------------
def load_model_weights():
    from qkeras.utils import load_qmodel
    model = load_qmodel(str(ROOT / "models" / "ids_cnn1d_qat_best.h5"))
    W = {}
    for name, scale in LAYER_SCALES.items():
        layer = model.get_layer(name)
        kq, bq = layer.get_quantizers()
        k, b = layer.get_weights()
        kq_v = np.array(kq(k.astype(np.float32))) * scale
        bq_v = np.array(bq(b.astype(np.float32))) * scale
        ki, bi = np.rint(kq_v).astype(np.int64), np.rint(bq_v).astype(np.int64)
        assert np.all(ki == kq_v) and np.all(bi == bq_v), f"{name}: non-integer codes"
        W[name] = (ki, bi)
        nz = np.count_nonzero(ki)
        print(f"  {name:7s} W{tuple(ki.shape)} range [{ki.min()},{ki.max()}] "
              f"nonzero {nz}/{ki.size}  b range [{bi.min()},{bi.max()}]")
    return model, W


def load_bench_samples():
    """Parse the 100 labeled CIC-IDS2017 vectors embedded in arm_ids_bench.cpp."""
    src = (ROOT / "arm_ids_bench.cpp").read_text()
    xs = re.search(r"TEST_X\[N_SAMPLES\]\[64\]\s*=\s*\{(.*?)\n\};", src, re.S).group(1)
    rows = re.findall(r"\{([^{}]*)\}", xs)
    X = np.array([[float(v.rstrip("f")) for v in r.split(",") if v.strip()] for r in rows])
    ys = re.search(r"TEST_Y\[N_SAMPLES\]\s*=\s*\{(.*?)\};", src, re.S).group(1)
    Y = np.array([int(v) for v in ys.split(",") if v.strip()])
    codes = np.rint(X * 16)
    assert np.all(codes == X * 16), "bench samples are not on the 1/16 grid"
    return np.clip(codes, -128, 127).astype(np.int64).reshape(-1, 16, 4), Y


def emit_weights_pkg(W, path):
    def flat(name, a, bits):
        """Packed vector: element n of a.reshape(-1) sits at [bits*n +: bits]."""
        v = a.reshape(-1)
        word = 0
        for n, x in enumerate(v):
            word |= (int(x) & ((1 << bits) - 1)) << (bits * n)
        nb = bits * len(v)
        # A Verilog literal cannot contain whitespace, so it stays on one line
        return f"  localparam logic [{nb - 1}:0] {name} = {nb}'h{word:0{(nb + 3) // 4}x};\n"

    w1, b1 = W["conv1"]; w2, b2 = W["conv2"]; w3, b3 = W["dense1"]; w4, b4 = W["dense2"]
    # Store weights output-major so each output unit's weight vector is one row.
    w1o = np.transpose(w1, (2, 0, 1)).reshape(16, 12)    # [f][k*4+c]
    w2o = np.transpose(w2, (2, 0, 1)).reshape(24, 48)    # [f][k*16+c]
    w3o = w3.T                                           # [u][i]
    w4o = w4.T                                           # [o][j]

    def acc_width(wo, b, xmax):
        # Worst-case |acc| over all inputs (bias enters at <<4), plus a sign bit
        bound = int((np.abs(wo).sum(axis=1) * xmax + np.abs(b) * 16).max())
        return bound.bit_length() + 1

    aw = [acc_width(w1o, b1, 128), acc_width(w2o, b2, 63),
          acc_width(w3o, b3, 63), acc_width(w4o, b4, 63)]
    assert max(aw) <= 24, f"accumulator widths {aw} exceed requant()'s 24-bit input"
    print(f"    accumulator widths conv1/conv2/dense1/dense2 = {aw}")
    out = f"""// ============================================================================
// AUTO-GENERATED by rtl/scripts/gen_rtl_data.py from models/ids_cnn1d_qat_best.h5
// Do not edit by hand. Integer weight codes for IDS-CNN1D-S, stored as flat
// packed vectors (portable to any Verilog tool). Element n is [bits*n +: bits]:
//   W_C1  n = f*12  + k*4  + c   int8, scale 32     B_C1  n = f   int8, scale 32
//   W_C2  n = f*48  + k*16 + c   int4, scale 2      B_C2  n = f   int4, scale 2
//   W_D1  n = u*120 + i          int4, scale 2      B_D1  n = u   int4, scale 2
//                                (i = t*24 + c, Keras Flatten order)
//   W_D2  n = o*32  + j          int8, scale 32     B_D2  n = o   int8, scale 32
// Accumulator widths are worst-case bounds over every possible input.
// ============================================================================
package ids_cnn1d_weights_pkg;

  localparam int AW_C1 = {aw[0]};
  localparam int AW_C2 = {aw[1]};
  localparam int AW_D1 = {aw[2]};
  localparam int AW_D2 = {aw[3]};

{flat("W_C1", w1o, 8)}{flat("B_C1", b1, 8)}
{flat("W_C2", w2o, 4)}{flat("B_C2", b2, 4)}
{flat("W_D1", w3o, 4)}{flat("B_D1", b3, 4)}
{flat("W_D2", w4o, 8)}{flat("B_D2", b4, 8)}
endpackage
"""
    path.write_text(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--random", type=int, default=4000, help="extra random test vectors")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    print("--> Loading QKeras model and extracting integer weights")
    model, W = load_model_weights()

    Xb, Yb = load_bench_samples()
    rng = np.random.default_rng(args.seed)
    # Random stress vectors: mix of narrow (typical) and full-range (saturating) inputs
    half = args.random // 2
    Xr = np.concatenate([
        np.clip(np.rint(rng.normal(0, 16, (half, 16, 4))), -128, 127),
        rng.integers(-128, 128, (args.random - half, 16, 4)),
    ]).astype(np.int64)
    X = np.concatenate([Xb, Xr])

    print(f"--> Integer reference on {len(X)} vectors ({len(Xb)} labeled + {len(Xr)} random)")
    logits, pred, _ = int_forward(X, W)
    assert np.abs(logits).max() < 2 ** 19, "dense2 accumulator overflow"

    # Bit-exactness vs QKeras: pre-softmax logits must equal int logits / 512.
    import tensorflow as tf
    pre = tf.keras.Model(model.input, model.get_layer("dense2").output)
    ref = pre.predict(X.astype(np.float32) / 16.0, batch_size=1024, verbose=0)
    mism = np.count_nonzero(np.rint(ref * 512).astype(np.int64) != logits)
    exact = np.array_equal(ref * 512, logits.astype(np.float64))
    print(f"    QKeras vs integer model: {mism} mismatching logits, exact={exact}")
    if not exact:
        sys.exit("ERROR: integer reference is not bit-exact with QKeras")
    acc = np.mean(pred[:len(Yb)] == Yb)
    print(f"    Accuracy on {len(Yb)} labeled bench samples: {acc * 100:.2f}%")

    emit_weights_pkg(W, RTL / "src" / "ids_cnn1d_weights_pkg.sv")
    (RTL / "data").mkdir(exist_ok=True)
    with open(RTL / "data" / "tb_inputs.hex", "w") as f:
        for s in X.reshape(len(X), 64):
            f.write(" ".join(f"{int(v) & 0xFF:02x}" for v in s) + "\n")
    with open(RTL / "data" / "tb_expected.hex", "w") as f:
        for lg, p in zip(logits, pred):
            f.write(" ".join(f"{int(v) & 0xFFFFF:05x}" for v in lg) + f" {int(p):x}\n")
    (RTL / "data" / "tb_labels.txt").write_text("\n".join(map(str, Yb)) + "\n")

    # Board demo ROMs, 128 entries: sample_rom.hex = 512-bit features,
    # sample_meta.hex = {label[2:0], golden_class[2:0]}.
    # Entries 0..99 are the labeled bench samples; the rest repeat them.
    with open(RTL / "data" / "sample_rom.hex", "w") as fr, \
         open(RTL / "data" / "sample_meta.hex", "w") as fm:
        for i in range(128):
            j = i % len(Xb)
            word = 0
            for c, v in enumerate(Xb[j].reshape(64)):
                word |= (int(v) & 0xFF) << (8 * c)
            fr.write(f"{word:0128x}\n")
            fm.write(f"{(int(Yb[j]) << 3) | int(pred[j]):02x}\n")

    # C header for the HPS test program (rtl/hps/ids_fpga_test.c)
    nb = len(Xb)
    rows = ",\n".join("  {" + ", ".join(str(int(v)) for v in s) + "}" for s in Xb.reshape(nb, 64))
    (RTL / "hps").mkdir(exist_ok=True)
    (RTL / "hps" / "ids_samples.h").write_text(
        "/* AUTO-GENERATED by rtl/scripts/gen_rtl_data.py: labeled CIC-IDS2017 samples */\n"
        f"#define IDS_N_SAMPLES {nb}\n"
        f"static const signed char IDS_X[{nb}][64] = {{\n{rows}\n}};\n"
        f"static const int IDS_LABEL[{nb}] = {{{', '.join(map(str, Yb))}}};\n"
        f"static const int IDS_GOLDEN[{nb}] = {{{', '.join(str(int(p)) for p in pred[:nb])}}};\n"
        f"static const int IDS_GOLDEN_LOGIT[{nb}][8] = {{\n"
        + ",\n".join("  {" + ", ".join(str(int(v)) for v in lg) + "}" for lg in logits[:nb])
        + "\n};\n")
    print(f"--> Wrote weights package and {len(X)} test vectors under {RTL}")


if __name__ == "__main__":
    main()
