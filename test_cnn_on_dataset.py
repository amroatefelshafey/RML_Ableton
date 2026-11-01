#!/usr/bin/env python3
"""Standalone script to test the quantized 1D-CNN (IDS-CNN1D-QAT) on a test dataset.

Usage:
    python test_cnn_on_dataset.py
    python test_cnn_on_dataset.py --x_test path/to/X_test.parquet --y_test path/to/y_test.parquet
    python test_cnn_on_dataset.py --max_samples 10000  # Quick dry-run
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.metrics import classification_report, confusion_matrix, precision_score, recall_score

# Suppress noisy TensorFlow startup logs
import os
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate Quantized 1D-CNN on CIC-IDS2017 test dataset."
    )
    parser.add_argument(
        "--x_test",
        type=str,
        default=None,
        help="Path to X_test (parquet or csv). Defaults to ../data/processed/X_test.parquet",
    )
    parser.add_argument(
        "--y_test",
        type=str,
        default=None,
        help="Path to y_test (parquet or csv). Defaults to ../data/processed/y_test.parquet",
    )
    parser.add_argument(
        "--config",
        type=str,
        default="config/frontend_config.json",
        help="Path to frontend_config.json",
    )
    parser.add_argument(
        "--model",
        type=str,
        default="models/ids_cnn1d_qat_best.h5",
        help="Path to quantized model .h5 file",
    )
    parser.add_argument(
        "--batch_size",
        type=int,
        default=4096,
        help="Inference batch size (default: 4096)",
    )
    parser.add_argument(
        "--max_samples",
        type=int,
        default=None,
        help="Optional limit on number of test samples to evaluate",
    )
    parser.add_argument(
        "--use_testbench",
        action="store_true",
        help="Evaluate on the 1,000 embedded testbench samples in ids_cnn1d_ip/tb_data/",
    )
    return parser.parse_args()


def load_config(config_path: Path) -> dict:
    if not config_path.exists():
        raise FileNotFoundError(f"Configuration file not found at: {config_path.resolve()}")
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_default_data_files() -> Tuple[Path, Path]:
    candidates_x = [
        Path("data/X_test.parquet"),
        Path("../data/processed/X_test.parquet"),
        Path("../../data/processed/X_test.parquet"),
    ]
    candidates_y = [
        Path("data/y_test.parquet"),
        Path("../data/processed/y_test.parquet"),
        Path("../../data/processed/y_test.parquet"),
    ]
    x_path = next((p for p in candidates_x if p.exists()), candidates_x[1])
    y_path = next((p for p in candidates_y if p.exists()), candidates_y[1])
    return x_path, y_path


def load_raw_data(x_path: Path, y_path: Path, max_samples: Optional[int] = None) -> Tuple[pd.DataFrame, pd.Series]:
    print(f"--> Loading features from: {x_path}")
    if x_path.suffix == ".parquet":
        df_x = pd.read_parquet(x_path)
    elif x_path.suffix == ".csv":
        df_x = pd.read_csv(x_path)
    else:
        raise ValueError(f"Unsupported file format for X: {x_path.suffix}")

    print(f"--> Loading labels from:   {y_path}")
    if y_path.suffix == ".parquet":
        df_y = pd.read_parquet(y_path)
    elif y_path.suffix == ".csv":
        df_y = pd.read_csv(y_path)
    else:
        raise ValueError(f"Unsupported file format for y: {y_path.suffix}")

    s_y = df_y.iloc[:, 0] if isinstance(df_y, pd.DataFrame) else df_y

    if max_samples is not None and len(df_x) > max_samples:
        print(f"--> Limiting to first {max_samples:,} samples for quick evaluation...")
        df_x = df_x.iloc[:max_samples]
        s_y = s_y.iloc[:max_samples]

    return df_x, s_y


def map_labels_to_8_classes(y_series: pd.Series, cfg: dict) -> np.ndarray:
    raw_15_names = [
        "BENIGN", "Bot", "DDoS", "DoS GoldenEye", "DoS Hulk", "DoS Slowhttptest",
        "DoS slowloris", "FTP - Patator", "Heartbleed", "Infiltration", "PortScan",
        "SSH - Patator", "Web Attack - Brute Force", "Web Attack - Sql Injection",
        "Web Attack - XSS"
    ]
    name_mapping = cfg.get("class_mapping_15_to_8", {})
    int_mapping = {idx: name_mapping.get(name, 0) for idx, name in enumerate(raw_15_names)}

    if pd.api.types.is_numeric_dtype(y_series):
        y_mapped = y_series.map(int_mapping)
    else:
        y_mapped = y_series.map(name_mapping)

    if y_mapped.isna().any():
        unmapped = y_series[y_mapped.isna()].unique()
        raise ValueError(f"Found unmapped labels in test dataset: {unmapped}")

    return y_mapped.values.astype(np.int64)


def preprocess_hardware_features(df_x: pd.DataFrame, cfg: dict) -> np.ndarray:
    expected_cols = cfg["feature_names"]
    if list(df_x.columns) == expected_cols:
        x_raw = df_x.values.astype(np.float64)
    elif all(c in df_x.columns for c in expected_cols):
        x_raw = df_x[expected_cols].values.astype(np.float64)
    else:
        print("[WARNING] Column names do not match expected feature list. Using positional columns.")
        x_raw = df_x.iloc[:, :len(expected_cols)].values.astype(np.float64)

    # 1. Signed-log1p transformation: sign(x) * log(1 + |x|)
    x_log = np.sign(x_raw) * np.log1p(np.abs(x_raw))

    # 2. RobustScaler transformation: (x - center) / scale
    center = np.array(cfg["scaler"]["center"], dtype=np.float64)
    scale = np.array(cfg["scaler"]["scale"], dtype=np.float64)
    x_scaled = (x_log - center) / scale

    # 3. Fixed-point quantization & clipping to ap_fixed<8,4>
    fp_min = cfg["fixed_point"]["min"]
    fp_max = cfg["fixed_point"]["max"]
    fp_lsb = cfg["fixed_point"]["lsb"]

    x_clipped = np.clip(x_scaled, fp_min, fp_max)
    x_quant = np.round(x_clipped / fp_lsb) * fp_lsb

    # 4. Zero-pad to 64 and reshape to (N, 16, 4)
    n_samples, n_feats = x_quant.shape
    pad_len = cfg.get("pad_length", 64)
    padded = np.zeros((n_samples, pad_len), dtype=np.float32)
    padded[:, :n_feats] = x_quant.astype(np.float32)

    cnn_shape = tuple(cfg.get("cnn_shape", [16, 4]))
    return padded.reshape((n_samples, *cnn_shape))


def main() -> None:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent

    config_path = script_dir / args.config if not Path(args.config).is_absolute() else Path(args.config)
    model_path = script_dir / args.model if not Path(args.model).is_absolute() else Path(args.model)

    print("==================================================================")
    print(" 🛡️  CIC-IDS2017 Edge FPGA CNN Test Harness (IDS-CNN1D-QAT)")
    print("==================================================================")
    cfg = load_config(config_path)

    if args.use_testbench:
        tb_x_path = script_dir / "ids_cnn1d_ip" / "tb_data" / "tb_input_features.dat"
        tb_y_path = script_dir / "ids_cnn1d_ip" / "tb_data" / "tb_expected_labels.dat"
        print(f"--> Using embedded testbench vectors: {tb_x_path}")
        raw_x = np.loadtxt(tb_x_path, dtype=np.float32)
        y_test = np.loadtxt(tb_y_path, dtype=np.int64)
        if args.max_samples is not None:
            raw_x = raw_x[:args.max_samples]
            y_test = y_test[:args.max_samples]
        x_test_cnn = raw_x.reshape((-1, 16, 4))
        print(f"Loaded {len(x_test_cnn):,} testbench samples (preprocessed ap_fixed<8,4> format).")
    else:
        if args.x_test and args.y_test:
            x_path, y_path = Path(args.x_test), Path(args.y_test)
        else:
            def_x, def_y = find_default_data_files()
            x_path = Path(args.x_test) if args.x_test else def_x
            y_path = Path(args.y_test) if args.y_test else def_y

        if not x_path.exists() or not y_path.exists():
            print(f"\nNotice: Test dataset files not found at:")
            print(f"  - Features: {x_path.resolve()}")
            print(f"  - Labels:   {y_path.resolve()}")
            print("\nOptions:")
            print("  1. Run with --use_testbench to test on the 1,000 embedded verification vectors:")
            print("     python test_cnn_on_dataset.py --use_testbench")
            print("  2. Specify your custom parquet/csv paths:")
            print("     python test_cnn_on_dataset.py --x_test <path/to/X_test.parquet> --y_test <path/to/y_test.parquet>\n")
            sys.exit(1)

        df_x, s_y = load_raw_data(x_path, y_path, max_samples=args.max_samples)
        print(f"Loaded {len(df_x):,} test samples.")

        print("--> Applying hardware-aligned preprocessing (ap_fixed<8,4>)...")
        x_test_cnn = preprocess_hardware_features(df_x, cfg)
        y_test = map_labels_to_8_classes(s_y, cfg)

    print(f"--> Loading QKeras model from: {model_path}")
    if not model_path.exists():
        print(f"Error: Model file not found at {model_path.resolve()}")
        sys.exit(1)

    from qkeras.utils import load_qmodel
    model = load_qmodel(str(model_path))

    print(f"--> Running inference on {len(x_test_cnn):,} samples (batch_size={args.batch_size})...")
    y_pred_probs = model.predict(x_test_cnn, batch_size=args.batch_size, verbose=1)
    y_pred = np.argmax(y_pred_probs, axis=1)

    # Metrics
    acc = np.mean(y_pred == y_test)
    y_test_bin = (y_test > 0).astype(int)
    y_pred_bin = (y_pred > 0).astype(int)

    attack_recall = recall_score(y_test_bin, y_pred_bin, zero_division=0)
    attack_prec = precision_score(y_test_bin, y_pred_bin, zero_division=0)
    fp_rate = np.sum((y_test_bin == 0) & (y_pred_bin == 1)) / max(1, np.sum(y_test_bin == 0))

    class_names = cfg.get("class_names_8", [f"Class_{i}" for i in range(8)])

    print("\n==================================================================")
    print(" 📊 Evaluation Results Summary")
    print("==================================================================")
    print(f" Total Samples Evaluated:      {len(y_test):,}")
    print(f" Overall Accuracy:             {acc * 100:.2f}%")
    print(f" Binary Attack Detection Recall: {attack_recall * 100:.2f}%")
    print(f" Binary Attack Precision:      {attack_prec * 100:.2f}%")
    print(f" Benign False Positive Rate:   {fp_rate * 100:.2f}%")
    print("==================================================================\n")

    print("Per-Class Classification Report:")
    print(classification_report(y_test, y_pred, target_names=class_names, digits=4, zero_division=0))

    print("Confusion Matrix (Rows: True, Cols: Predicted):")
    cm = confusion_matrix(y_test, y_pred, labels=list(range(len(class_names))))
    header = "True \\ Pred | " + " | ".join(f"{name[:8]:>8}" for name in class_names)
    print(header)
    print("-" * len(header))
    for idx, row in enumerate(cm):
        row_str = f"{class_names[idx][:11]:<11} | " + " | ".join(f"{val:>8,}" for val in row)
        print(row_str)

    print("\n✅ Evaluation successfully completed!")


if __name__ == "__main__":
    main()
