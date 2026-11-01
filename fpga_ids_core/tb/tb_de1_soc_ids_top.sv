// ============================================================================
// Testbench for the standalone board demo (de1_soc_ids_top): presses KEY[1]
// for each of the 16 ROM samples and checks HEX5 shows a match, then runs
// free-run mode (SW[9]) and checks every result still matches.
// ============================================================================
`timescale 1ns/1ps
module tb_de1_soc_ids_top;
    logic       CLOCK_50 = 1'b0;
    logic [3:0] KEY = 4'hF;
    logic [9:0] SW = '0;
    logic [9:0] LEDR;
    logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    always #10 CLOCK_50 = ~CLOCK_50;

    de1_soc_ids_top dut (.*);

    // Active-low 7-segment pattern -> hex digit, -1 if unknown
    function automatic int seg2hex(input logic [6:0] s);
        logic [6:0] t [16] = '{7'h3F, 7'h06, 7'h5B, 7'h4F, 7'h66, 7'h6D, 7'h7D, 7'h07,
                               7'h7F, 7'h6F, 7'h77, 7'h7C, 7'h39, 7'h5E, 7'h79, 7'h71};
        for (int i = 0; i < 16; i++) if (~t[i] == s) return i;
        return -1;
    endfunction

    int errors = 0, runs = 0;

    initial begin
        KEY[0] = 1'b0;
        repeat (3) @(posedge CLOCK_50);
        KEY[0] = 1'b1;

        for (int s = 0; s < 16; s++) begin
            SW[3:0] = 4'(s);
            repeat (2) @(posedge CLOCK_50);
            KEY[1] = 1'b0; repeat (5) @(posedge CLOCK_50); KEY[1] = 1'b1;
            repeat (40) @(posedge CLOCK_50);
            $display("SW=%2d  class=%0d %s  sample=%0d  match=%0h  latency=%0d  LEDR=%b",
                     s, seg2hex(HEX0), seg2hex(HEX1) == 10 ? "attack" : "benign",
                     seg2hex(HEX4), seg2hex(HEX5), 16 * seg2hex(HEX3) + seg2hex(HEX2), LEDR);
            if (seg2hex(HEX5) != 0 || seg2hex(HEX4) != s || 16 * seg2hex(HEX3) + seg2hex(HEX2) != 29 ||
                LEDR[8:1] != 8'(1 << seg2hex(HEX0)) || LEDR[0] != (seg2hex(HEX0) != 0))
                errors++;
        end

        SW[9] = 1'b1;
        fork
            repeat (64 * 40) @(posedge CLOCK_50);
            forever begin
                @(posedge dut.engine_done); #1;
                @(posedge CLOCK_50); #1;      // results latch on done
                runs++;
                if (seg2hex(HEX5) != 0) errors++;
            end
        join_any
        disable fork;
        $display("free-run: %0d inferences", runs);
        if (runs < 30) errors++;

        $display("RESULT: %0d errors", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end
endmodule
