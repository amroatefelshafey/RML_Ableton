// ============================================================================
// Testbench for ids_cnn1d_hps_avmm: drives the Avalon-MM slave the way the HPS
// driver does and checks every result against the golden vectors.
//   1. Every vector: write FEAT[0..15] (autostart), poll RESULT for a new SEQ,
//      read LOGIT[0..7].
//   2. Back-to-back: write the next sample while the engine is busy, start it
//      with CTRL.START, and check the queued start runs.
//   3. IRQ enable, assert and write-1-to-clear; ID register; byte-wide writes.
// Pass the folder with +DATA=<dir> (default ../../rtl/data).
// ============================================================================
`timescale 1ns/1ps
module tb_ids_cnn1d_hps_avmm;
    logic        clk = 1'b0, rst_n = 1'b0;
    logic [4:0]  address = '0;
    logic        read = 1'b0, write = 1'b0;
    logic [31:0] writedata = '0, readdata;
    logic [3:0]  byteenable = 4'hF;
    logic        irq, coe_attack, coe_busy, coe_valid;
    logic [2:0]  coe_class;

    always #10 clk = ~clk;

    ids_cnn1d_hps_avmm dut (
        .clk(clk), .rst_n(rst_n),
        .avs_address(address), .avs_read(read), .avs_write(write),
        .avs_writedata(writedata), .avs_byteenable(byteenable), .avs_readdata(readdata),
        .irq(irq), .coe_class(coe_class), .coe_attack(coe_attack),
        .coe_busy(coe_busy), .coe_valid(coe_valid)
    );

    task automatic wr(input logic [4:0] a, input logic [31:0] d, input logic [3:0] be = 4'hF);
        @(negedge clk);
        address = a; writedata = d; byteenable = be; write = 1'b1;
        @(negedge clk);
        write = 1'b0; byteenable = 4'hF;
    endtask

    task automatic rd(input logic [4:0] a, output logic [31:0] d);
        @(negedge clk);
        address = a; read = 1'b1;
        @(negedge clk);
        read = 1'b0;
        @(posedge clk); #1;           // readLatency = 1
        d = readdata;
    endtask

    // Golden vectors
    localparam int MAXV = 5000;
    logic [7:0]  vin  [0:MAXV-1][0:63];
    logic [19:0] vlog [0:MAXV-1][0:7];
    logic [2:0]  vcls [0:MAXV-1];
    int          nv;

    task automatic load_vectors(input string dir);
        integer fi, fe, r, b;
        fi = $fopen({dir, "/tb_inputs.hex"}, "r");
        fe = $fopen({dir, "/tb_expected.hex"}, "r");
        if (fi == 0 || fe == 0) $fatal(1, "cannot open vectors in %s", dir);
        nv = 0;
        while (nv < MAXV) begin
            r = 0;
            for (int i = 0; i < 64; i++) begin r += $fscanf(fi, "%h", b); vin[nv][i] = b[7:0]; end
            if (r != 64) break;
            for (int i = 0; i < 8; i++) begin r = $fscanf(fe, "%h", b); vlog[nv][i] = b[19:0]; end
            r = $fscanf(fe, "%h", b); vcls[nv] = b[2:0];
            nv++;
        end
    endtask

    task automatic write_sample(input int s);
        for (int w = 0; w < 16; w++)
            wr(5'd16 + 5'(w), {vin[s][4*w+3], vin[s][4*w+2], vin[s][4*w+1], vin[s][4*w]});
    endtask

    int errors = 0;

    task automatic check_result(input int s, input logic [15:0] seq_expected);
        logic [31:0] res, lg;
        rd(5'd0, res);
        if (res[31:16] != seq_expected || res[2:0] != vcls[s] || res[3] != (vcls[s] != 0) ||
            !res[4] || res[15:8] != 8'd29) begin
            if (errors < 10)
                $display("sample %0d: RESULT 0x%08h, expected class %0d seq %0d", s, res, vcls[s], seq_expected);
            errors++;
        end
        for (int k = 0; k < 8; k++) begin
            rd(5'd8 + 5'(k), lg);
            if (lg != 32'($signed(vlog[s][k]))) begin
                if (errors < 10) $display("sample %0d logit %0d: 0x%08h", s, k, lg);
                errors++;
            end
        end
    endtask

    initial begin
        string dir;
        logic [31:0] d;
        logic [15:0] seq;
        int polls;
        if (!$value$plusargs("DATA=%s", dir)) dir = "../../rtl/data";
        load_vectors(dir);

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        rd(5'd3, d);
        if (d != 32'h1D5C_0002) begin $display("ID reads 0x%08h", d); errors++; end
        rd(5'd1, d);
        if (d != 32'h2) begin $display("CTRL reset value 0x%08h", d); errors++; end

        // 1. One sample at a time, autostart on FEAT[15]
        seq = 16'd0;
        for (int s = 0; s < nv; s++) begin
            write_sample(s);
            polls = 0;
            do begin rd(5'd0, d); polls++; end while (d[31:16] == seq && polls < 100);
            seq++;
            check_result(s, seq);
        end
        $display("autostart: %0d vectors, %0d errors so far", nv, errors);

        // 2. Queue a start while busy: autostart off, explicit CTRL.START.
        //    FEAT is copied when the engine starts, so overwriting it while
        //    the first run computes must not affect that run.
        wr(5'd1, 32'h0);
        write_sample(0);
        wr(5'd1, 32'h1);                       // run A on sample 0
        rd(5'd0, d);
        if (!d[5]) begin $display("engine not busy after START"); errors++; end
        wr(5'd1, 32'h1);                       // run B, queued: engine still busy
        rd(5'd0, d);
        if (!d[6]) begin $display("start not queued while busy, RESULT 0x%08h", d); errors++; end
        do rd(5'd0, d); while (d[31:16] != seq + 16'd1);
        seq++;
        rd(5'd0, d);
        if (d[2:0] != vcls[0] || !d[5] || d[4]) begin
            $display("run A: RESULT 0x%08h (expected class %0d, run B busy)", d, vcls[0]); errors++;
        end
        write_sample(3);                       // overwrite FEAT while run B computes
        do rd(5'd0, d); while (d[31:16] != seq + 16'd1);
        seq++;
        check_result(0, seq);                  // run B used the FEAT copied at its start

        // 3. IRQ, then byte-wide feature writes
        wr(5'd1, 32'h4);                       // IRQ_EN, autostart off
        wr(5'd2, 32'h1);                       // clear pending
        if (irq) begin $display("irq high after clear"); errors++; end
        for (int i = 0; i < 64; i++)
            wr(5'd16 + 5'(i / 4), {4{vin[2][i]}}, 4'b0001 << (i % 4));
        wr(5'd1, 32'h5);                       // START, keep IRQ_EN
        wait (irq);
        seq++;
        check_result(2, seq);
        wr(5'd2, 32'h1);
        @(posedge clk); #1;
        if (irq) begin $display("irq did not clear"); errors++; end

        $display("RESULT: %0d errors", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end
endmodule
