// ============================================================================
// DE1-SoC Top-Level Entity for Cyclone V 5CSEMA5F31C6 FPGA
// Real-Time Hardware-Accelerated Network Intrusion Detection System
// ============================================================================
module de1_soc_ids_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,
    input  logic [9:0]  SW,

    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1,
    output logic [6:0]  HEX2,
    output logic [6:0]  HEX3,
    output logic [6:0]  HEX4,
    output logic [6:0]  HEX5
);

    logic clk;
    logic rst_n;
    assign clk   = CLOCK_50;
    assign rst_n = KEY[0];

    // Engine signals
    logic               start_pulse;
    logic signed [7:0]  active_features [0:63];
    logic               engine_busy;
    logic               engine_done;
    logic [2:0]         engine_pred;
    logic               engine_attack;
    logic [15:0]        engine_latency;
    logic signed [20:0] debug_logits [0:7];

    // ROM Verification signals
    logic [3:0]         active_sample_idx;
    logic signed [7:0]  rom_sample_data [0:63];
    logic [2:0]         rom_expected_class;

    // Registered Results
    logic [2:0]  reg_pred;
    logic        reg_attack;
    logic [15:0] reg_latency;
    logic [3:0]  reg_sample;
    logic [2:0]  reg_expected;

    // Button edge detector for KEY[1]
    logic key1_d1, key1_d2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key1_d1 <= 1'b1;
            key1_d2 <= 1'b1;
        end else begin
            key1_d1 <= KEY[1];
            key1_d2 <= key1_d1;
        end
    end
    wire key1_press = (key1_d2 && !key1_d1);

    // Continuous free-run trigger counter for SW[9]=1
    logic [5:0] free_run_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) free_run_cnt <= 6'd0;
        else free_run_cnt <= free_run_cnt + 1'b1;
    end
    wire free_run_trigger = (free_run_cnt == 6'd63);

    // Automatic sample advancement in free-run mode
    logic [3:0] auto_sample_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            auto_sample_idx <= 4'd0;
        end else if (SW[9] && engine_done) begin
            auto_sample_idx <= auto_sample_idx + 1'b1;
        end
    end

    assign active_sample_idx = SW[9] ? auto_sample_idx : SW[3:0];

    // Instantiate Verification Sample ROM
    sample_rom u_rom (
        .sample_idx     (active_sample_idx),
        .sample_data    (rom_sample_data),
        .expected_class (rom_expected_class)
    );

    assign active_features = rom_sample_data;
    assign start_pulse     = SW[9] ? (free_run_trigger && !engine_busy) : key1_press;

    // Instantiate 1D-CNN Inference Core
    ids_cnn1d_engine u_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start_pulse),
        .input_features (active_features),
        .busy           (engine_busy),
        .done           (engine_done),
        .pred_class     (engine_pred),
        .is_attack      (engine_attack),
        .latency_cycles (engine_latency),
        .debug_logits   (debug_logits)
    );

    // Latch results on completion
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_pred     <= 3'd0;
            reg_attack   <= 1'b0;
            reg_latency  <= 16'd29;
            reg_sample   <= 4'd0;
            reg_expected <= 3'd0;
        end else if (engine_done) begin
            reg_pred     <= engine_pred;
            reg_attack   <= engine_attack;
            reg_latency  <= engine_latency;
            reg_sample   <= active_sample_idx;
            reg_expected <= rom_expected_class;
        end
    end

    // ========================================================================
    // LED Indicators
    // ========================================================================
    // LEDR[0]: Alarm LED (Bright Red on ATTACK, OFF on BENIGN)
    // LEDR[8:1]: One-hot class indicator
    // LEDR[9]: Busy indicator
    always_comb begin
        LEDR[0] = reg_attack;
        LEDR[8:1] = 8'd1 << reg_pred;
        LEDR[9] = engine_busy;
    end

    // ========================================================================
    // 7-Segment Displays
    // ========================================================================
    // HEX0: Predicted Class (0 to 7)
    // HEX1: Attack / Benign ('A'=Attack, 'b'=Benign)
    // HEX2: Latency Low Nibble
    // HEX3: Latency High Nibble
    // HEX4: Sample Index
    // HEX5: Match Indicator (0 = match with expected, F = mismatch)
    hex_decoder u_hex0 (
        .hex_digit ({1'b0, reg_pred}),
        .seg       (HEX0)
    );

    hex_decoder u_hex1 (
        .hex_digit (reg_attack ? 4'hA : 4'hB),
        .seg       (HEX1)
    );

    hex_decoder u_hex2 (
        .hex_digit (reg_latency[3:0]),
        .seg       (HEX2)
    );

    hex_decoder u_hex3 (
        .hex_digit (reg_latency[7:4]),
        .seg       (HEX3)
    );

    hex_decoder u_hex4 (
        .hex_digit (reg_sample),
        .seg       (HEX4)
    );

    hex_decoder u_hex5 (
        .hex_digit ((reg_pred == reg_expected) ? 4'h0 : 4'hF),
        .seg       (HEX5)
    );

endmodule
