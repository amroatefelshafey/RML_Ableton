// ============================================================================
// System-level checks:
//   1. de1_soc_ids_top in benchmark mode: the on-board statistics that drive
//      the HEX displays must read 97 correct / 15-cycle interval / 0 mismatches.
//   2. de1_soc_ids_top in single-sample mode: KEY[1] classifies SW[6:0].
//   3. ids_cnn1d_avmm: all vectors through the Avalon-MM register interface,
//      class and logits checked against the reference.
// ============================================================================
`timescale 1ns/1ps

module tb_system;
    import ids_cnn1d_weights_pkg::AW_D2;

    localparam int NV = 300;     // vectors pushed through the Avalon wrapper

    logic clk = 0;
    always #10 clk = ~clk;
    int errors = 0;

    // ---------------- DE1-SoC top ----------------
    logic [3:0] KEY = 4'b1110;
    logic [9:0] SW  = 10'd0;
    logic [9:0] LEDR;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    de1_soc_ids_top u_top (.CLOCK_50(clk), .*);

    // ---------------- Avalon wrapper ----------------
    logic        rst_n = 0;
    logic [4:0]  avs_address;
    logic        avs_write = 0, avs_read = 0;
    logic [31:0] avs_writedata, avs_readdata;

    ids_cnn1d_avmm u_avmm (.clk, .rst_n, .avs_address, .avs_write, .avs_writedata,
                           .avs_read, .avs_readdata);

    logic [7:0]  vin  [0:4100*64-1];
    logic [19:0] vexp [0:4100*9-1];
    initial begin
        $readmemh("data/tb_inputs.hex", vin);
        $readmemh("data/tb_expected.hex", vexp);
    end

    task automatic bus_write(input int a, input logic [31:0] d);
        @(posedge clk);
        avs_address <= a; avs_writedata <= d; avs_write <= 1;
        @(posedge clk);
        avs_write <= 0;
    endtask

    task automatic bus_read(input int a, output logic [31:0] d);
        @(posedge clk);
        avs_address <= a; avs_read <= 1;
        @(posedge clk);
        avs_read <= 0;
        #1 d = avs_readdata;     // read latency 1
    endtask

    task automatic check(input string what, input longint got, input longint exp);
        if (got !== exp) begin
            $display("FAIL %s: got %0d expected %0d", what, got, exp);
            errors++;
        end else begin
            $display("ok   %s = %0d", what, got);
        end
    endtask

    initial begin
        logic [31:0] d;
        int nbad;

        // ---- 1. board top, benchmark mode ----
        repeat (4) @(posedge clk);
        KEY[0] = 1'b1;
        SW[9]  = 1'b1;
        // two full passes of 100 samples (~15 cycles each) plus margin
        repeat (2 * 100 * 15 + 400) @(posedge clk);
        check("top bench: correct per pass", u_top.last_correct, 97);
        check("top bench: cycles per sample", u_top.last_ii, 15);
        check("top bench: golden mismatches", u_top.mismatches, 0);
        check("top bench: LEDR[0] (mismatch)", LEDR[0], 0);

        // ---- 2. board top, single-sample mode (sample 1 is PortScan) ----
        SW = 10'd1;
        repeat (10) @(posedge clk);
        KEY[1] = 1'b0;
        repeat (10) @(posedge clk);
        KEY[1] = 1'b1;
        repeat (60) @(posedge clk);
        check("top single: sample index", u_top.r_idx, 1);
        check("top single: predicted class", u_top.r_class, 3);
        check("top single: LEDR[0] (attack)", LEDR[0], 1);

        // ---- 3. Avalon-MM wrapper ----
        rst_n = 1;
        bus_read(27, d);
        check("avmm: ID", d, 32'h1D5C_0001);
        nbad = 0;
        for (int v = 0; v < NV; v++) begin
            do bus_read(16, d); while (!d[0]);
            for (int w = 0; w < 16; w++)
                bus_write(w, {vin[v*64+4*w+3], vin[v*64+4*w+2], vin[v*64+4*w+1], vin[v*64+4*w]});
            bus_write(16, 1);
            do bus_read(16, d); while (!d[1]);
            for (int k = 0; k < 8; k++) begin
                bus_read(18 + k, d);
                if ($signed(d) != $signed(vexp[v*9+k])) nbad++;
            end
            bus_read(17, d);
            if (!d[31] || d[2:0] != vexp[v*9+8][2:0] || d[3] != (vexp[v*9+8] != 0)) nbad++;
        end
        check("avmm: mismatching fields", nbad, 0);
        bus_read(16, d);
        check("avmm: result popped", d[1], 0);
        bus_read(26, d);
        check("avmm: COUNT", d, NV);

        $display("============================================================");
        $display(" tb_system RESULT: %s (%0d failures)", errors == 0 ? "PASS" : "FAIL", errors);
        $display("============================================================");
        $finish;
    end
endmodule
