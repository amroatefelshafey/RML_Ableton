// ============================================================================
// DE1-SoC standalone demo for ids_cnn1d_engine (FPGA fabric only, no HPS).
// 100 real CIC-IDS2017 samples live in on-chip ROM (data/sample_rom.hex).
//
// KEY[0]  reset (active low)
//
// SW[9]=0  single-sample mode: SW[6:0] selects a sample, KEY[1] classifies it
//   HEX0      predicted class        HEX1  'A' attack / 'b' benign
//   HEX2      true label             HEX3  golden class (Python reference)
//   HEX5:4    sample index (hex)
//   LEDR[0]   attack                 LEDR[8:1] one-hot predicted class
//
// SW[9]=1  benchmark mode: streams samples 0..99 back-to-back at full rate
//   HEX1:0    correct predictions per 100-sample pass (decimal, expect 97)
//   HEX3:2    measured cycles between accepted samples (hex, expect 0F)
//   HEX5:4    mismatches vs golden reference, saturating (hex, expect 00)
//   LEDR[0]   any golden mismatch seen since reset
//   LEDR[9]   benchmark running
// ============================================================================
module de1_soc_ids_top (
    input  logic        CLOCK_50,
    input  logic [3:0]  KEY,
    input  logic [9:0]  SW,
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
);
    import ids_cnn1d_weights_pkg::AW_D2;

    logic clk, rst_n;
    assign clk = CLOCK_50;

    // Synchronized reset and inputs
    logic [1:0] rst_sync;
    always_ff @(posedge clk or negedge KEY[0])
        if (!KEY[0]) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    assign rst_n = rst_sync[1];

    logic [9:0] sw_s1, sw;
    logic [2:0] key1_s;
    always_ff @(posedge clk) begin
        sw_s1  <= SW;
        sw     <= sw_s1;
        key1_s <= {key1_s[1:0], KEY[1]};
    end
    wire key1_press = key1_s[2] && !key1_s[1];
    wire bench      = sw[9];

    // ------------------------------------------------------------------------
    // Sample ROMs (M10K). Registered read: data valid one cycle after address.
    // ------------------------------------------------------------------------
    logic [511:0] rom_feat [0:127];
    logic [5:0]   rom_meta [0:127];
    initial begin
        $readmemh("../data/sample_rom.hex", rom_feat);
        $readmemh("../data/sample_meta.hex", rom_meta);
    end

    logic [6:0]   rd_addr;
    logic [511:0] feat_q;
    always_ff @(posedge clk) feat_q <= rom_feat[rd_addr];

    // ------------------------------------------------------------------------
    // Engine
    // ------------------------------------------------------------------------
    logic               in_valid, in_ready, out_valid;
    logic [2:0]         out_class;
    logic [8*AW_D2-1:0] out_logits;

    ids_cnn1d_engine u_engine (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(feat_q),
        .out_valid(out_valid), .out_ready(1'b1),
        .out_class(out_class), .out_logits(out_logits)
    );

    wire in_fire = in_valid && in_ready;

    // Issue control: rd_addr is presented, feat_q is valid on the next cycle.
    logic rom_ok;          // feat_q corresponds to rd_addr
    logic single_req;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_addr    <= '0;
            rom_ok     <= 1'b0;
            single_req <= 1'b0;
        end else if (bench) begin
            single_req <= 1'b0;
            if (in_fire) begin
                rd_addr <= (rd_addr >= 7'd99) ? 7'd0 : rd_addr + 7'd1;
                rom_ok  <= 1'b0;
            end else begin
                rom_ok  <= 1'b1;
            end
        end else begin
            if (in_fire)    single_req <= 1'b0;
            if (key1_press) single_req <= 1'b1;
            rom_ok  <= (rd_addr == sw[6:0]);
            rd_addr <= sw[6:0];
        end
    end
    assign in_valid = rom_ok && (bench || single_req);

    // In-flight sample indices, so each result can be paired with its label.
    logic [6:0] tag_fifo [0:7];
    logic [2:0] tag_wp, tag_rp;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_wp <= '0;
            tag_rp <= '0;
        end else begin
            if (in_fire)   tag_wp <= tag_wp + 3'd1;
            if (out_valid) tag_rp <= tag_rp + 3'd1;
        end
    end
    always_ff @(posedge clk)
        if (in_fire) tag_fifo[tag_wp] <= rd_addr;

    wire [6:0] out_idx    = tag_fifo[tag_rp];
    wire [5:0] out_meta   = rom_meta[out_idx];
    wire [2:0] out_label  = out_meta[5:3];
    wire [2:0] out_golden = out_meta[2:0];

    // ------------------------------------------------------------------------
    // Result registers and benchmark statistics
    // ------------------------------------------------------------------------
    logic [2:0]  r_class, r_label, r_golden;
    logic [6:0]  r_idx;
    logic [6:0]  pass_correct, last_correct;
    logic [7:0]  mismatches;
    logic [15:0] ii_cnt, last_ii;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_class <= '0; r_label <= '0; r_golden <= '0; r_idx <= '0;
            pass_correct <= '0; last_correct <= '0; mismatches <= '0;
            ii_cnt <= '0; last_ii <= '0;
        end else begin
            ii_cnt <= in_fire ? 16'd1 : (ii_cnt == 16'hFFFF ? ii_cnt : ii_cnt + 16'd1);
            if (in_fire) last_ii <= ii_cnt;

            if (out_valid) begin
                r_class  <= out_class;
                r_label  <= out_label;
                r_golden <= out_golden;
                r_idx    <= out_idx;
                if (out_class != out_golden && mismatches != 8'hFF)
                    mismatches <= mismatches + 8'd1;
                if (bench) begin
                    if (out_idx == 7'd99) begin
                        last_correct <= pass_correct + (out_class == out_label);
                        pass_correct <= '0;
                    end else begin
                        pass_correct <= pass_correct + (out_class == out_label);
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Displays
    // ------------------------------------------------------------------------
    wire [3:0] acc_tens = last_correct / 10;
    wire [3:0] acc_ones = last_correct % 10;

    logic [3:0] d0, d1, d2, d3, d4, d5;
    always_comb begin
        if (bench) begin
            {d1, d0} = {acc_tens, acc_ones};
            {d3, d2} = last_ii[7:0];
            {d5, d4} = mismatches;
        end else begin
            d0 = {1'b0, r_class};
            d1 = (r_class != 3'd0) ? 4'hA : 4'hB;
            d2 = {1'b0, r_label};
            d3 = {1'b0, r_golden};
            {d5, d4} = {1'b0, r_idx};
        end
        LEDR[0]   = bench ? (mismatches != 8'd0) : (r_class != 3'd0);
        LEDR[8:1] = 8'd1 << r_class;
        LEDR[9]   = bench;
    end

    hex_decoder u_hex0 (.hex_digit(d0), .seg(HEX0));
    hex_decoder u_hex1 (.hex_digit(d1), .seg(HEX1));
    hex_decoder u_hex2 (.hex_digit(d2), .seg(HEX2));
    hex_decoder u_hex3 (.hex_digit(d3), .seg(HEX3));
    hex_decoder u_hex4 (.hex_digit(d4), .seg(HEX4));
    hex_decoder u_hex5 (.hex_digit(d5), .seg(HEX5));
endmodule
