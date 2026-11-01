// ============================================================================
// DE1-SoC top level: HPS + IDS-CNN1D engine on the HPS-to-FPGA bridge.
// The HPS writes features and reads results through ids_cnn1d_hps_avmm
// (HPS address 0xC000_0000); see ids_hps_client.c.
//
// KEY[0]  FPGA-side reset (the HPS reset also resets the engine)
// LEDR[0] attack, LEDR[8:1] one-hot class, LEDR[9] engine busy
// HEX0    class of the last result, HEX1 'A' attack / 'b' benign
// ============================================================================
module de1_soc_ids_hps_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,

    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,

    // HPS DDR3
    output logic [14:0] HPS_DDR3_ADDR,
    output logic [2:0]  HPS_DDR3_BA,
    output logic        HPS_DDR3_CAS_N,
    output logic        HPS_DDR3_CKE,
    output logic        HPS_DDR3_CK_N,
    output logic        HPS_DDR3_CK_P,
    output logic        HPS_DDR3_CS_N,
    output logic [3:0]  HPS_DDR3_DM,
    inout  wire  [31:0] HPS_DDR3_DQ,
    inout  wire  [3:0]  HPS_DDR3_DQS_N,
    inout  wire  [3:0]  HPS_DDR3_DQS_P,
    output logic        HPS_DDR3_ODT,
    output logic        HPS_DDR3_RAS_N,
    output logic        HPS_DDR3_RESET_N,
    input  logic        HPS_DDR3_RZQ,
    output logic        HPS_DDR3_WE_N
);

    logic [2:0] ids_class;
    logic       ids_attack, ids_busy, ids_valid;

    soc_system u_soc (
        .clk_clk            (CLOCK_50),
        .reset_reset_n      (KEY[0]),

        .ids_status_class   (ids_class),
        .ids_status_attack  (ids_attack),
        .ids_status_busy    (ids_busy),
        .ids_status_valid   (ids_valid),

        .memory_mem_a       (HPS_DDR3_ADDR),
        .memory_mem_ba      (HPS_DDR3_BA),
        .memory_mem_ck      (HPS_DDR3_CK_P),
        .memory_mem_ck_n    (HPS_DDR3_CK_N),
        .memory_mem_cke     (HPS_DDR3_CKE),
        .memory_mem_cs_n    (HPS_DDR3_CS_N),
        .memory_mem_ras_n   (HPS_DDR3_RAS_N),
        .memory_mem_cas_n   (HPS_DDR3_CAS_N),
        .memory_mem_we_n    (HPS_DDR3_WE_N),
        .memory_mem_reset_n (HPS_DDR3_RESET_N),
        .memory_mem_dq      (HPS_DDR3_DQ),
        .memory_mem_dqs     (HPS_DDR3_DQS_P),
        .memory_mem_dqs_n   (HPS_DDR3_DQS_N),
        .memory_mem_odt     (HPS_DDR3_ODT),
        .memory_mem_dm      (HPS_DDR3_DM),
        .memory_oct_rzqin   (HPS_DDR3_RZQ)
    );

    always_comb begin
        LEDR[0]   = ids_valid && ids_attack;
        LEDR[8:1] = ids_valid ? (8'd1 << ids_class) : 8'd0;
        LEDR[9]   = ids_busy;
    end

    hex_decoder u_hex0 (
        .hex_digit ({1'b0, ids_class}),
        .seg       (HEX0)
    );

    hex_decoder u_hex1 (
        .hex_digit (ids_attack ? 4'hA : 4'hB),
        .seg       (HEX1)
    );

endmodule
