// ============================================================================
// IDS-CNN1D-S inference engine — bit-exact with the QKeras model
// (models/ids_cnn1d_qat_best.h5), verified by rtl/tb/tb_ids_cnn1d_engine.sv.
//
// Dataflow pipeline with every weight hard-wired as a constant, so zero
// weights cost nothing and the 4-bit layers (weights in {-1,-.5,0,.5,1})
// reduce to shifts and adder trees.
//
//   S1  conv1 + ReLU + maxpool  one conv1 position / cycle      14 cycles
//   S2  conv2 + ReLU            one conv2 position / cycle       5 cycles
//   S3  dense1 + ReLU           fully parallel                   1 cycle
//   S4  dense2 (logits)         fully parallel                   1 cycle
//   S5  argmax                                                   1 cycle
//
// Stages hand off through valid/ready registers, so samples overlap: a new
// sample is accepted every 15 cycles (3.33 M inferences/s at 50 MHz).
// Latency from in_fire to out_valid is 24 cycles with no backpressure.
//
// Input : in_data[8*i +: 8] = feature i as int8 (ap_fixed<8,4>, value*16),
//         with feature i = x[t = i/4][c = i%4] of the (16,4) input tensor.
// Output: out_class = argmax (first maximum wins, same as np.argmax);
//         out_logits[AW_D2*k +: AW_D2] = dense2 logit k, signed, value*512.
// ============================================================================
module ids_cnn1d_engine (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    output logic        in_ready,
    input  logic [511:0] in_data,

    output logic        out_valid,
    input  logic        out_ready,
    output logic [2:0]  out_class,
    output logic [8*ids_cnn1d_weights_pkg::AW_D2-1:0] out_logits
);
    import ids_cnn1d_weights_pkg::*;

    // ReLU requantization: round-half-even(acc / 2^sh), saturate to [0, 63].
    // Matches quantized_relu(6,2), which uses tf.round on value*16.
    function automatic logic [5:0] requant(input logic signed [23:0] acc, input int sh);
        logic signed [23:0] q;
        logic [23:0]        rem, half;
        logic               up;
        q    = acc >>> sh;
        rem  = acc & ((24'd1 << sh) - 24'd1);
        half = 24'd1 << (sh - 1);
        up   = (rem > half) || ((rem == half) && q[0]);
        q    = q + $signed({23'd0, up});
        if (q <= 0)       requant = 6'd0;
        else if (q > 63)  requant = 6'd63;
        else              requant = q[5:0];
    endfunction

    // Pipeline handshakes (stage k "takes" from stage k-1 when it has room)
    logic s1_busy, s1_full, s2_busy, s2_full, s3_valid, s4_valid;
    logic s2_take, s3_take, s4_take, s5_take, in_fire;

    assign s5_take  = s4_valid && (!out_valid || out_ready);
    assign s4_take  = s3_valid && (!s4_valid || s5_take);
    assign s3_take  = s2_full  && (!s3_valid || s4_take);
    assign s2_take  = s1_full  && !s2_busy && (!s2_full || s3_take);
    assign in_ready = !s1_busy && (!s1_full || s2_take);
    assign in_fire  = in_valid && in_ready;

    // ========================================================================
    // S1: conv1 (16 filters, K=3, 4 ch) + ReLU + MaxPool(2)
    // x_sr shifts one timestep per cycle, so the conv window is always x_sr[0..2].
    // ========================================================================
    logic signed [7:0] x_sr    [0:15][0:3];
    logic [3:0]        s1_cnt;
    logic [5:0]        h1      [0:15];
    logic [5:0]        h1_hold [0:15];        // even position awaiting its pool partner
    logic [5:0]        p1_sr   [0:6][0:15];   // pooled output, shifted in as produced

    logic [13*AW_C1-1:0]     c1_terms [0:15];
    logic signed [AW_C1-1:0] c1_acc   [0:15];

    always_comb begin
        for (int f = 0; f < 16; f++) begin
            for (int i = 0; i < 12; i++)
                c1_terms[f][i*AW_C1 +: AW_C1] = $signed(x_sr[i/4][i%4]) * $signed(W_C1[8*(12*f+i) +: 8]);
            c1_terms[f][12*AW_C1 +: AW_C1] = $signed(B_C1[8*f +: 8]) <<< 4;
        end
    end

    generate
        for (genvar f = 0; f < 16; f++) begin : g_c1
            adder_tree #(.N(13), .W(AW_C1)) u_sum (.terms(c1_terms[f]), .sum(c1_acc[f]));
        end
    endgenerate

    always_comb
        for (int f = 0; f < 16; f++) h1[f] = requant(c1_acc[f], 5);   // scale 512 -> 16

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_busy <= 1'b0;
            s1_full <= 1'b0;
            s1_cnt  <= '0;
        end else begin
            if (s2_take) s1_full <= 1'b0;
            if (in_fire) begin
                s1_busy <= 1'b1;
                s1_cnt  <= '0;
            end else if (s1_busy) begin
                s1_cnt <= s1_cnt + 4'd1;
                if (s1_cnt == 4'd13) begin
                    s1_busy <= 1'b0;
                    s1_full <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (in_fire) begin
            for (int t = 0; t < 16; t++)
                for (int c = 0; c < 4; c++)
                    x_sr[t][c] <= in_data[8*(4*t+c) +: 8];
        end else if (s1_busy) begin
            for (int t = 0; t < 15; t++)
                for (int c = 0; c < 4; c++)
                    x_sr[t][c] <= x_sr[t+1][c];
            if (!s1_cnt[0]) begin
                for (int f = 0; f < 16; f++) h1_hold[f] <= h1[f];
            end else begin
                for (int p = 0; p < 6; p++)
                    for (int f = 0; f < 16; f++)
                        p1_sr[p][f] <= p1_sr[p+1][f];
                for (int f = 0; f < 16; f++)
                    p1_sr[6][f] <= (h1[f] > h1_hold[f]) ? h1[f] : h1_hold[f];
            end
        end
    end

    // ========================================================================
    // S2: conv2 (24 filters, K=3, 16 ch) + ReLU
    // ========================================================================
    logic [5:0] s2_sr [0:6][0:15];
    logic [5:0] h2_sr [0:4][0:23];    // h2_sr[t][c] = conv2 output at position t
    logic [2:0] s2_cnt;
    logic [5:0] h2    [0:23];

    logic [49*AW_C2-1:0]     c2_terms [0:23];
    logic signed [AW_C2-1:0] c2_acc   [0:23];

    always_comb begin
        for (int f = 0; f < 24; f++) begin
            for (int i = 0; i < 48; i++)
                c2_terms[f][i*AW_C2 +: AW_C2] = $signed({1'b0, s2_sr[i/16][i%16]}) * $signed(W_C2[4*(48*f+i) +: 4]);
            c2_terms[f][48*AW_C2 +: AW_C2] = $signed(B_C2[4*f +: 4]) <<< 4;
        end
    end

    generate
        for (genvar f = 0; f < 24; f++) begin : g_c2
            adder_tree #(.N(49), .W(AW_C2)) u_sum (.terms(c2_terms[f]), .sum(c2_acc[f]));
        end
    endgenerate

    always_comb
        for (int f = 0; f < 24; f++) h2[f] = requant(c2_acc[f], 1);   // scale 32 -> 16

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_busy <= 1'b0;
            s2_full <= 1'b0;
            s2_cnt  <= '0;
        end else begin
            if (s3_take) s2_full <= 1'b0;
            if (s2_take) begin
                s2_busy <= 1'b1;
                s2_cnt  <= '0;
            end else if (s2_busy) begin
                s2_cnt <= s2_cnt + 3'd1;
                if (s2_cnt == 3'd4) begin
                    s2_busy <= 1'b0;
                    s2_full <= 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (s2_take) begin
            for (int p = 0; p < 7; p++)
                for (int c = 0; c < 16; c++)
                    s2_sr[p][c] <= p1_sr[p][c];
        end else if (s2_busy) begin
            for (int p = 0; p < 6; p++)
                for (int c = 0; c < 16; c++)
                    s2_sr[p][c] <= s2_sr[p+1][c];
            for (int t = 0; t < 4; t++)
                for (int c = 0; c < 24; c++)
                    h2_sr[t][c] <= h2_sr[t+1][c];
            for (int c = 0; c < 24; c++)
                h2_sr[4][c] <= h2[c];
        end
    end

    // ========================================================================
    // S3: flatten + dense1 (120 -> 32) + ReLU      (flat index i = t*24 + c)
    // ========================================================================
    logic [5:0] h3_reg [0:31];

    logic [121*AW_D1-1:0]    d1_terms [0:31];
    logic signed [AW_D1-1:0] d1_acc   [0:31];

    always_comb begin
        for (int u = 0; u < 32; u++) begin
            for (int i = 0; i < 120; i++)
                d1_terms[u][i*AW_D1 +: AW_D1] = $signed({1'b0, h2_sr[i/24][i%24]}) * $signed(W_D1[4*(120*u+i) +: 4]);
            d1_terms[u][120*AW_D1 +: AW_D1] = $signed(B_D1[4*u +: 4]) <<< 4;
        end
    end

    generate
        for (genvar u = 0; u < 32; u++) begin : g_d1
            adder_tree #(.N(121), .W(AW_D1)) u_sum (.terms(d1_terms[u]), .sum(d1_acc[u]));
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       s3_valid <= 1'b0;
        else if (s3_take) s3_valid <= 1'b1;
        else if (s4_take) s3_valid <= 1'b0;
    end

    always_ff @(posedge clk)
        if (s3_take)
            for (int u = 0; u < 32; u++) h3_reg[u] <= requant(d1_acc[u], 1);

    // ========================================================================
    // S4: dense2 (32 -> 8), linear logits at scale 512
    // ========================================================================
    logic signed [AW_D2-1:0] logit_reg [0:7];

    logic [33*AW_D2-1:0]     d2_terms [0:7];
    logic signed [AW_D2-1:0] d2_acc   [0:7];

    always_comb begin
        for (int o = 0; o < 8; o++) begin
            for (int j = 0; j < 32; j++)
                d2_terms[o][j*AW_D2 +: AW_D2] = $signed({1'b0, h3_reg[j]}) * $signed(W_D2[8*(32*o+j) +: 8]);
            d2_terms[o][32*AW_D2 +: AW_D2] = $signed(B_D2[8*o +: 8]) <<< 4;
        end
    end

    generate
        for (genvar o = 0; o < 8; o++) begin : g_d2
            adder_tree #(.N(33), .W(AW_D2)) u_sum (.terms(d2_terms[o]), .sum(d2_acc[o]));
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       s4_valid <= 1'b0;
        else if (s4_take) s4_valid <= 1'b1;
        else if (s5_take) s4_valid <= 1'b0;
    end

    always_ff @(posedge clk)
        if (s4_take)
            for (int o = 0; o < 8; o++) logit_reg[o] <= d2_acc[o];

    // ========================================================================
    // S5: argmax as a 3-level tree; ties go to the lower index (= np.argmax)
    // ========================================================================
    logic [2:0]              am_idx [0:6];
    logic signed [AW_D2-1:0] am_val [0:6];

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            am_idx[i] = (logit_reg[2*i] >= logit_reg[2*i+1]) ? 3'(2*i) : 3'(2*i+1);
            am_val[i] = (logit_reg[2*i] >= logit_reg[2*i+1]) ? logit_reg[2*i] : logit_reg[2*i+1];
        end
        for (int i = 0; i < 2; i++) begin
            am_idx[4+i] = (am_val[2*i] >= am_val[2*i+1]) ? am_idx[2*i] : am_idx[2*i+1];
            am_val[4+i] = (am_val[2*i] >= am_val[2*i+1]) ? am_val[2*i] : am_val[2*i+1];
        end
        am_idx[6] = (am_val[4] >= am_val[5]) ? am_idx[4] : am_idx[5];
        am_val[6] = (am_val[4] >= am_val[5]) ? am_val[4] : am_val[5];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                     out_valid <= 1'b0;
        else if (s5_take)               out_valid <= 1'b1;
        else if (out_ready)             out_valid <= 1'b0;
    end

    always_ff @(posedge clk)
        if (s5_take) begin
            out_class <= am_idx[6];
            for (int o = 0; o < 8; o++) out_logits[AW_D2*o +: AW_D2] <= logit_reg[o];
        end

endmodule
