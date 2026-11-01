// Active-low 7-segment display decoder for DE1-SoC
module hex_decoder (
    input  logic [3:0] hex_digit,
    output logic [6:0] seg
);
    // seg[0]=a, seg[1]=b, seg[2]=c, seg[3]=d, seg[4]=e, seg[5]=f, seg[6]=g
    always_comb begin
        case (hex_digit)
            4'h0: seg = ~7'b0111111; // 0
            4'h1: seg = ~7'b0000110; // 1
            4'h2: seg = ~7'b1011011; // 2
            4'h3: seg = ~7'b1001111; // 3
            4'h4: seg = ~7'b1100110; // 4
            4'h5: seg = ~7'b1101101; // 5
            4'h6: seg = ~7'b1111101; // 6
            4'h7: seg = ~7'b0000111; // 7
            4'h8: seg = ~7'b1111111; // 8
            4'h9: seg = ~7'b1101111; // 9
            4'hA: seg = ~7'b1110111; // A (Attack)
            4'hB: seg = ~7'b1111100; // b (Benign)
            4'hC: seg = ~7'b0111001; // C
            4'hD: seg = ~7'b1011110; // d
            4'hE: seg = ~7'b1111001; // E
            4'hF: seg = ~7'b1110001; // F
            default: seg = 7'b1111111;
        endcase
    end
endmodule
