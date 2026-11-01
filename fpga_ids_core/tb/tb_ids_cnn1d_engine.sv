// ============================================================================
// Bit-exact testbench for ids_cnn1d_engine.
// Golden vectors come from rtl/scripts/gen_rtl_data.py, whose integer model is
// checked against QKeras:
//   tb_inputs.hex    one sample per line, 64 x int8 (hex)
//   tb_expected.hex  8 logits (20-bit two's complement, x512) + class per line
// Pass the folder with +DATA=<dir> (default ../../rtl/data).
// ============================================================================
`timescale 1ns/1ps
module tb_ids_cnn1d_engine;
    logic clk = 1'b0, rst_n = 1'b0, start = 1'b0;
    logic signed [7:0]  features [0:63];
    logic               busy, done, is_attack;
    logic [2:0]         pred_class;
    logic [15:0]        latency_cycles;
    logic signed [20:0] logits [0:7];

    always #10 clk = ~clk;   // 50 MHz

    ids_cnn1d_engine dut (
        .clk(clk), .rst_n(rst_n), .start(start), .input_features(features),
        .busy(busy), .done(done), .pred_class(pred_class), .is_attack(is_attack),
        .latency_cycles(latency_cycles), .debug_logits(logits)
    );

    string  dir;
    integer fi, fe, n, r, b, logit_err, class_err;
    integer exp_v [0:8];

    initial begin
        if (!$value$plusargs("DATA=%s", dir)) dir = "../../rtl/data";
        fi = $fopen({dir, "/tb_inputs.hex"}, "r");
        fe = $fopen({dir, "/tb_expected.hex"}, "r");
        if (fi == 0 || fe == 0) $fatal(1, "cannot open vectors in %s", dir);

        n = 0; logit_err = 0; class_err = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        forever begin
            r = 0;
            for (int i = 0; i < 64; i++) begin
                r += $fscanf(fi, "%h", b);
                features[i] = b[7:0];
            end
            if (r != 64) break;
            for (int i = 0; i < 9; i++) r = $fscanf(fe, "%h", exp_v[i]);

            @(negedge clk) start = 1'b1;
            @(negedge clk) start = 1'b0;
            @(posedge done); #1;

            for (int i = 0; i < 8; i++)
                if (logits[i] != 21'($signed(exp_v[i][19:0]))) logit_err++;
            if (pred_class != exp_v[8][2:0] || is_attack != (exp_v[8] != 0)) begin
                if (class_err < 5)
                    $display("sample %0d: class %0d, expected %0d", n, pred_class, exp_v[8]);
                class_err++;
            end
            if (latency_cycles != 16'd29) $error("latency_cycles = %0d", latency_cycles);
            n++;
        end

        $display("RESULT: %0d vectors, %0d logit mismatches, %0d class mismatches",
                 n, logit_err, class_err);
        if (n == 0 || logit_err != 0 || class_err != 0) $display("FAIL");
        else                                            $display("PASS");
        $finish;
    end
endmodule
