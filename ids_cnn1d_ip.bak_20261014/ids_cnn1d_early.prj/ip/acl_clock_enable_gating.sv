// (c) 2025-2026 Intel Corporation.                            
// Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
// and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
// and/or other countries. Other marks and brands may be claimed as the property  
// of others. See Trademarks on intel.com for full list of Intel trademarks or    
// the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
// Your use of Intel Corporation's design tools, logic functions and other        
// software and tools, and its AMPP partner logic functions, and any output       
// files any of the foregoing (including device programming or simulation         
// files), and any associated documentation or information are expressly subject  
// to the terms and conditions of the Altera Program License Subscription         
// Agreement, Intel MegaCore Function License Agreement, or other applicable      
// license agreement, including, without limitation, that your use is for the     
// sole purpose of programming logic devices manufactured by Intel and sold by    
// Intel or its authorized distributors.  Please refer to the applicable          
// agreement for further details.                                                 


// acl_clock_enable_gating
// This module implements the clock enable PR safe circuitry suggested by Quartus Partial Reconfiguration User Guide.

`default_nettype none

module acl_clock_enable_gating (
    input  wire      clk,
    input  wire      freeze,
    input  wire      clock_enable_input,
    output wire      gated_clock_enable
);

    // clock enable PR safe circuitry
    reg ce_reg;
    reg [1:0] ce_delay;

    always @(posedge clk, posedge freeze) begin
        if (freeze) begin
            ce_delay <= 2'b0;
        end
        else begin
            ce_delay <= {ce_delay[0], 1'b1};
        end
    end

    always @(posedge clk, negedge ce_delay[1]) begin
        if (~ce_delay[1]) begin
            ce_reg <= 1'b0;
        end
        else begin
            ce_reg <= clock_enable_input;
        end
    end

    assign gated_clock_enable = ce_reg;

endmodule

`default_nettype wire