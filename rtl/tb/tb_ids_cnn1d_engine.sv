// ============================================================================
// Self-checking testbench for ids_cnn1d_engine.
// Streams every vector in data/tb_inputs.hex through the engine and compares
// all 8 logits and the argmax against data/tb_expected.hex, which the integer
// reference model in scripts/gen_rtl_data.py proved bit-exact with QKeras.
//
// Plusargs: +STRESS=1  randomize input gaps and output backpressure
//           +NVEC=n    number of vectors to run (default: all)
// ============================================================================
`timescale 1ns/1ps

module tb_ids_cnn1d_engine;
    import ids_cnn1d_weights_pkg::AW_D2;

    localparam int MAXV   = 4100;
    localparam int NLABEL = 100;

    logic clk = 0, rst_n = 0;
    always #10 clk = ~clk;   // 50 MHz

    logic         in_valid, in_ready, out_valid, out_ready;
    logic [511:0] in_data;
    logic [2:0]   out_class;
    logic [8*AW_D2-1:0] out_logits;

    ids_cnn1d_engine dut (.*);

    logic [7:0]  vin  [0:MAXV*64-1];
    logic [19:0] vexp [0:MAXV*9-1];
    int          labels [0:NLABEL-1];

    int nvec, stress;
    int n_sent = 0, n_recv = 0, n_err = 0, n_correct = 0;
    longint t_first_in = -1, t_last_in, t_first_out = -1, t_last_out;
    longint cyc = 0;
    longint fire_cyc [0:MAXV-1];
    longint lat_min = 1 << 30, lat_max = 0;

    always @(posedge clk) cyc <= cyc + 1;

    initial begin
        int fd;
        $readmemh("data/tb_inputs.hex", vin);
        $readmemh("data/tb_expected.hex", vexp);
        fd = $fopen("data/tb_labels.txt", "r");
        for (int i = 0; i < NLABEL; i++) void'($fscanf(fd, "%d", labels[i]));
        $fclose(fd);
        if (!$value$plusargs("NVEC=%d", nvec))     nvec = MAXV;
        if (!$value$plusargs("STRESS=%d", stress)) stress = 0;
    end

    // ---------------- driver ----------------
    always @(posedge clk) begin
        if (!rst_n) begin
            in_valid <= 1'b0;
        end else begin
            if (in_valid && in_ready) begin
                fire_cyc[n_sent] = cyc;
                if (t_first_in < 0) t_first_in = cyc;
                t_last_in = cyc;
                n_sent++;
            end
            if ((!in_valid || in_ready) ) begin
                if (n_sent < nvec && (!stress || $urandom_range(0, 3) != 0)) begin
                    in_valid <= 1'b1;
                    for (int i = 0; i < 64; i++) in_data[8*i +: 8] <= vin[n_sent*64 + i];
                end else begin
                    in_valid <= 1'b0;
                end
            end
        end
    end

    // ---------------- backpressure ----------------
    always @(posedge clk)
        out_ready <= !rst_n ? 1'b0 : (!stress || $urandom_range(0, 2) != 0);

    // ---------------- monitor / checker ----------------
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            automatic int  v   = n_recv;
            automatic bit  bad = 0;
            automatic longint lat = cyc - fire_cyc[v];
            for (int k = 0; k < 8; k++)
                if ($signed(out_logits[AW_D2*k +: AW_D2]) != $signed(vexp[v*9 + k])) bad = 1;
            if (out_class != vexp[v*9 + 8][2:0]) bad = 1;
            if (bad) begin
                n_err++;
                if (n_err <= 10) begin
                    $display("MISMATCH vec %0d: class hw=%0d ref=%0d", v, out_class, vexp[v*9+8]);
                    for (int k = 0; k < 8; k++)
                        $display("   logit[%0d] hw=%0d ref=%0d", k,
                                 $signed(out_logits[AW_D2*k +: AW_D2]), $signed(vexp[v*9 + k]));
                end
            end
            if (v < NLABEL && out_class == labels[v]) n_correct++;
            if (lat < lat_min) lat_min = lat;
            if (lat > lat_max) lat_max = lat;
            if (t_first_out < 0) t_first_out = cyc;
            t_last_out = cyc;
            n_recv++;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
        wait (n_recv == nvec);
        @(posedge clk);
        $display("============================================================");
        $display(" ids_cnn1d_engine: %0d vectors, stress=%0d", nvec, stress);
        $display("   bit-exact mismatches : %0d", n_err);
        if (nvec >= NLABEL)
            $display("   accuracy (100 labeled CIC-IDS2017 samples): %0d%%", n_correct);
        $display("   latency in_fire->out : %0d..%0d cycles", lat_min, lat_max);
        if (nvec > 1)
            $display("   input interval       : %.2f cycles/sample",
                     real'(t_last_in - t_first_in) / (nvec - 1));
        $display("   RESULT: %s", n_err == 0 ? "PASS" : "FAIL");
        $display("============================================================");
        $finish;
    end

    initial begin
        #(64'd20 * 64'd1_000_000);
        $display("TIMEOUT: sent %0d, received %0d", n_sent, n_recv);
        $finish;
    end
endmodule
