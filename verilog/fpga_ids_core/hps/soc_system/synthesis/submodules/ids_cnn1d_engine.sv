// ============================================================================
// 1D-CNN Network Intrusion Detection Engine for Cyclone V FPGA
// Bit-exact implementation of QKeras IDS-CNN1D-S model
//
// Integer formats (value x scale):
//   input               ap_fixed<8,4>        int8  x16
//   conv1/dense2 W, b   quantized_bits(8,2)  int8  x32
//   conv2/dense1 W, b   quantized_bits(4,2)  int4  x2
//   ReLU outputs        quantized_relu(6,2)  uint6 x16, round half to even,
//                                            saturate at 63
//   logits              dense2 accumulator   x512
//
// Timing at 50 MHz: each cycle does either the multiplies / partial sums or
// the final sum + requantization, never both. The conv layers walk their
// input with shift registers (window always at positions 0..2) so no
// runtime-indexed muxes sit in the datapath, and outputs shift in the same way.
//
// Latency: 29 cycles from start to done (latency_cycles reports 29).
//   CONV1 16 (14 positions + 2 pipeline), POOL1 1, CONV2 6 (5 + 1),
//   DENSE1 2, DENSE2 3, ARGMAX 1
// ============================================================================
import ids_cnn1d_weights::*;

module ids_cnn1d_engine (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic signed [7:0]  input_features [0:63],

    output logic               busy,
    output logic               done,
    output logic [2:0]         pred_class,
    output logic               is_attack,
    output logic [15:0]        latency_cycles,
    output logic signed [20:0] debug_logits [0:7]
);

    typedef enum logic [3:0] {
        IDLE,
        CONV1,
        POOL1,
        CONV2,
        DENSE1_PART,
        DENSE1_SUM,
        DENSE2_MUL,
        DENSE2_PART,
        DENSE2_SUM,
        ARGMAX,
        DONE
    } state_t;

    state_t state;
    logic [15:0] cycle_cnt;
    logic [4:0]  step;           // cycle within CONV1 / CONV2

    // Layer Storage Buffers
    logic signed [7:0] in_buf [0:15][0:3];
    logic [5:0]        conv1_out [0:13][0:15]; // ap_ufixed<6,2>
    logic [5:0]        pool1_out [0:6][0:15];  // ap_ufixed<6,2>
    logic [5:0]        conv2_out [0:4][0:23];  // ap_ufixed<6,2>
    logic [5:0]        dense1_out [0:31];      // ap_ufixed<6,2>
    logic signed [20:0] dense2_out [0:7];

    // Pipeline registers
    logic signed [15:0] conv1_prod [0:15][0:2][0:3]; // in x W, scale 512
    logic signed [19:0] conv1_acc  [0:15];           // scale 512
    logic signed [19:0] conv2_part [0:23][0:2];      // per kernel tap, scale 32
    logic signed [19:0] dense1_part [0:31][0:4];     // per time step, scale 32
    logic signed [14:0] dense2_prod [0:7][0:31];     // in x W, scale 512
    logic signed [20:0] dense2_part [0:7][0:3];      // per 8 inputs, scale 512

    assign debug_logits = dense2_out;

    // quantized_relu(6,2) on an accumulator at scale 16 * 2**sh:
    // ReLU, divide by 2**sh rounding half to even (tf.round), saturate to 63.
    function automatic logic [5:0] relu_requant(input logic signed [19:0] acc, input int sh);
        logic signed [19:0] q;
        if (acc <= 20'sd0) return 6'd0;
        q = (acc + ((20'sd1 <<< (sh - 1)) - 20'sd1) + ((acc >>> sh) & 20'sd1)) >>> sh;
        return (q > 20'sd63) ? 6'd63 : q[5:0];
    endfunction

    // ------------------------------------------------------------------------
    // FSM & Datapath
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
            pred_class <= 3'd0;
            is_attack  <= 1'b0;
            latency_cycles <= 16'd0;
            cycle_cnt <= 16'd0;
            step <= 5'd0;
        end else begin
            done <= 1'b0; // default

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        cycle_cnt <= 16'd0;
                        step <= 5'd0;
                        // Latch input tensor: 64 samples into (16, 4)
                        for (int t = 0; t < 16; t++) begin
                            for (int c = 0; c < 4; c++) begin
                                in_buf[t][c] <= input_features[t * 4 + c];
                            end
                        end
                        state <= CONV1;
                    end
                end

                // ------------------------------------------------------------
                // Layer 1: Conv1D, 14 positions through a 3-stage pipeline
                //   step 0..13   multiply window in_buf[0..2], shift in_buf
                //   step 1..14   sum 12 products + bias
                //   step 2..15   requantize, shift into conv1_out[13]
                // ------------------------------------------------------------
                CONV1: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    step <= step + 1'b1;

                    if (step < 5'd14) begin
                        for (int f = 0; f < 16; f++)
                            for (int k = 0; k < 3; k++)
                                for (int c = 0; c < 4; c++)
                                    conv1_prod[f][k][c] <= $signed(in_buf[k][c]) * $signed(W_CONV1[k][c][f]);
                        for (int t = 0; t < 15; t++)
                            in_buf[t] <= in_buf[t + 1];
                    end

                    if (step >= 5'd1 && step <= 5'd14) begin
                        for (int f = 0; f < 16; f++) begin
                            automatic logic signed [19:0] acc = $signed(B_CONV1[f]) * 20'sd16; // scale 512
                            for (int k = 0; k < 3; k++)
                                for (int c = 0; c < 4; c++)
                                    acc += conv1_prod[f][k][c];
                            conv1_acc[f] <= acc;
                        end
                    end

                    if (step >= 5'd2) begin
                        for (int t = 0; t < 13; t++)
                            conv1_out[t] <= conv1_out[t + 1];
                        for (int f = 0; f < 16; f++)
                            conv1_out[13][f] <= relu_requant(conv1_acc[f], 5); // scale 512 -> 16
                    end

                    if (step == 5'd15) begin
                        step <= 5'd0;
                        state <= POOL1;
                    end
                end

                // ------------------------------------------------------------
                // Layer 2: MaxPool1D (1 cycle)
                // ------------------------------------------------------------
                POOL1: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int t = 0; t < 7; t++) begin
                        for (int f = 0; f < 16; f++) begin
                            pool1_out[t][f] <= (conv1_out[2*t][f] > conv1_out[2*t+1][f]) ?
                                               conv1_out[2*t][f] : conv1_out[2*t+1][f];
                        end
                    end
                    state <= CONV2;
                end

                // ------------------------------------------------------------
                // Layer 3: Conv1D #2, 5 positions through a 2-stage pipeline
                //   step 0..4   per-tap partial sums of window pool1_out[0..2],
                //               shift pool1_out
                //   step 1..5   add taps + bias, requantize, shift into
                //               conv2_out[4]
                // ------------------------------------------------------------
                CONV2: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    step <= step + 1'b1;

                    if (step < 5'd5) begin
                        for (int f = 0; f < 24; f++) begin
                            for (int k = 0; k < 3; k++) begin
                                automatic logic signed [19:0] acc = 20'sd0; // scale 32
                                for (int c = 0; c < 16; c++)
                                    acc += $signed({1'b0, pool1_out[k][c]}) * $signed(W_CONV2[k][c][f]);
                                conv2_part[f][k] <= acc;
                            end
                        end
                        for (int t = 0; t < 6; t++)
                            pool1_out[t] <= pool1_out[t + 1];
                    end

                    if (step >= 5'd1) begin
                        for (int t = 0; t < 4; t++)
                            conv2_out[t] <= conv2_out[t + 1];
                        for (int f = 0; f < 24; f++) begin
                            automatic logic signed [19:0] acc = $signed(B_CONV2[f]) * 20'sd16;
                            for (int k = 0; k < 3; k++)
                                acc += conv2_part[f][k];
                            conv2_out[4][f] <= relu_requant(acc, 1); // scale 32 -> 16
                        end
                    end

                    if (step == 5'd5) begin
                        step <= 5'd0;
                        state <= DENSE1_PART;
                    end
                end

                // ------------------------------------------------------------
                // Layer 4: Dense1, 120 -> 32 (2 cycles)
                // Flatten index i = t*24 + c. Every weight index is a loop
                // constant, so the 4-bit weights fold into shifts and adds.
                // ------------------------------------------------------------
                DENSE1_PART: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int j = 0; j < 32; j++) begin
                        for (int t = 0; t < 5; t++) begin
                            automatic logic signed [19:0] acc = 20'sd0; // scale 32
                            for (int c = 0; c < 24; c++)
                                acc += $signed({1'b0, conv2_out[t][c]}) * $signed(W_DENSE1[t * 24 + c][j]);
                            dense1_part[j][t] <= acc;
                        end
                    end
                    state <= DENSE1_SUM;
                end

                DENSE1_SUM: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int j = 0; j < 32; j++) begin
                        automatic logic signed [19:0] acc = $signed(B_DENSE1[j]) * 20'sd16;
                        for (int t = 0; t < 5; t++)
                            acc += dense1_part[j][t];
                        dense1_out[j] <= relu_requant(acc, 1); // scale 32 -> 16
                    end
                    state <= DENSE2_MUL;
                end

                // ------------------------------------------------------------
                // Layer 5: Dense2, 32 -> 8 logits (3 cycles)
                // ------------------------------------------------------------
                DENSE2_MUL: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int c = 0; c < 8; c++)
                        for (int j = 0; j < 32; j++)
                            dense2_prod[c][j] <= $signed({1'b0, dense1_out[j]}) * $signed(W_DENSE2[j][c]);
                    state <= DENSE2_PART;
                end

                DENSE2_PART: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int c = 0; c < 8; c++) begin
                        for (int g = 0; g < 4; g++) begin
                            automatic logic signed [20:0] acc = 21'sd0; // scale 512
                            for (int j = 8 * g; j < 8 * g + 8; j++)
                                acc += dense2_prod[c][j];
                            dense2_part[c][g] <= acc;
                        end
                    end
                    state <= DENSE2_SUM;
                end

                DENSE2_SUM: begin
                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int c = 0; c < 8; c++) begin
                        automatic logic signed [20:0] acc = $signed(B_DENSE2[c]) * 21'sd16;
                        for (int g = 0; g < 4; g++)
                            acc += dense2_part[c][g];
                        dense2_out[c] <= acc;
                    end
                    state <= ARGMAX;
                end

                // ------------------------------------------------------------
                // Argmax & Threat Decision (1 cycle, 3-level compare tree)
                // The right (higher-index) side wins only when strictly
                // greater, so the first maximum wins, as in np.argmax.
                // ------------------------------------------------------------
                ARGMAX: begin
                    automatic logic signed [20:0] v1 [0:3];
                    automatic logic [2:0]         i1 [0:3];
                    automatic logic signed [20:0] v2 [0:1];
                    automatic logic [2:0]         i2 [0:1];
                    automatic logic [2:0]         max_idx;

                    cycle_cnt <= cycle_cnt + 1'b1;
                    for (int p = 0; p < 4; p++) begin
                        if (dense2_out[2*p+1] > dense2_out[2*p]) begin
                            v1[p] = dense2_out[2*p+1];
                            i1[p] = 3'(2*p+1);
                        end else begin
                            v1[p] = dense2_out[2*p];
                            i1[p] = 3'(2*p);
                        end
                    end
                    for (int p = 0; p < 2; p++) begin
                        if (v1[2*p+1] > v1[2*p]) begin
                            v2[p] = v1[2*p+1];
                            i2[p] = i1[2*p+1];
                        end else begin
                            v2[p] = v1[2*p];
                            i2[p] = i1[2*p];
                        end
                    end
                    max_idx = (v2[1] > v2[0]) ? i2[1] : i2[0];

                    pred_class <= max_idx;
                    is_attack  <= (max_idx != 3'd0);
                    state <= DONE;
                end

                // ------------------------------------------------------------
                // Done State
                // ------------------------------------------------------------
                DONE: begin
                    latency_cycles <= cycle_cnt;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
