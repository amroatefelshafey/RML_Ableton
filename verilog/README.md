# Move_ME: Cyclone V FPGA CNN Inference Package

This folder contains the **minimum self-contained components** to test the quantized 1D-CNN model on the CIC-IDS2017 dataset and port the hardware IP core to an Intel Cyclone V (DE1-SoC) Quartus workstation.

---

## Folder Structure

```
Move_ME/
├── ids_cnn1d_ip/             # Intel HLS C++ hardware IP package for Cyclone V
│   ├── build_hls_ip.sh       # One-click synthesis & testbench execution script
│   ├── Makefile              # Testbench build configuration
│   ├── myproject_test.cpp    # C-simulation testbench runner
│   ├── firmware/             # Top-level HLS core, weights, parameters, defines
│   └── tb_data/              # 1,000 real verification vectors for C-simulation
├── models/
│   └── ids_cnn1d_qat_best.h5 # Serialized mixed-precision QKeras model
├── config/
│   └── frontend_config.json  # Preprocessing scaling factors & ap_fixed<8,4> bounds
├── test_cnn_on_dataset.py    # Standalone evaluation script on test dataset
├── reqs.txt                  # Minimal Python dependencies for testing
└── README.md
```

---

## 1. Quick Python Verification (PC / Workstation)

### Install minimal requirements:
```bash
pip install -r reqs.txt
```

### Run model evaluation on the test dataset:
```bash
# Default (looks for data/processed/X_test.parquet):
python test_cnn_on_dataset.py

# Custom data paths:
python test_cnn_on_dataset.py --x_test path/to/X_test.parquet --y_test path/to/y_test.parquet

# Fast dry-run on 10,000 samples:
python test_cnn_on_dataset.py --max_samples 10000

# Immediate verification on embedded 1,000 testbench samples (no external dataset needed):
python test_cnn_on_dataset.py --use_testbench
```

---

## 2. Porting to the Quartus Machine

### Step 1: Copy `ids_cnn1d_ip` to your Quartus machine:
```bash
scp -r ids_cnn1d_ip user@quartus-workstation:~/
```

### Step 2: Run C-Simulation & HLS Synthesis:
```bash
cd ~/ids_cnn1d_ip
./build_hls_ip.sh
```
This runs:
1. `make test` — Compiles and executes C-simulation comparing C++ HLS predictions against reference Python outputs.
2. `i++ -march=5CSEMA5F31C6 --clock 8ns firmware/myproject.cpp -o build_ids_core` — Synthesizes the Cyclone V hardware core.

### Step 3: Check Synthesis Reports:
Open `build_ids_core.prj/reports/report.html` to confirm:
- **Initiation Interval ($II$):** $\le 60$ clock cycles ($\ge 1\text{ Gbps}$ wire speed)
- **DSP Block Usage:** $\le 87$ blocks (budgeted $\le 20$ blocks)
- **Clock Frequency:** $\ge 125\text{ MHz}$ ($8\text{ ns}$)
