// ============================================================================
// Avalon-MM slave wrapper for ids_cnn1d_engine, for the HPS-to-FPGA
// lightweight bridge (32-bit data, word addressing, read latency 1).
//
// Word  Byte   R/W  Register
// 0-15  0x00   W    IN[0..15]  features 4w..4w+3, feature 4w in bits [7:0]
// 16    0x40   W    CTRL       bit0: 1 = submit IN[] to the engine
//              R    STATUS     bit0: IN[] free (previous submit accepted)
//                              bit1: a result is waiting in RESULT
// 17    0x44   R    RESULT     [2:0] class, [3] attack, [31] valid.
//                              Reading it with valid=1 pops the result.
// 18-25 0x48   R    LOGIT[0..7] logits of the waiting result, signed, x512
//                              (read these before popping RESULT)
// 26    0x68   R    COUNT      results produced since reset
// 27    0x6C   R    ID         0x1D5C_0001
//
// Driver loop: poll STATUS.bit0, write IN[0..15], write CTRL=1;
//              poll STATUS.bit1, optionally read LOGIT[], read RESULT.
// ============================================================================
module ids_cnn1d_avmm (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [4:0]  avs_address,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    input  logic        avs_read,
    output logic [31:0] avs_readdata
);
    import ids_cnn1d_weights_pkg::AW_D2;

    logic [511:0]       in_buf;
    logic               in_pending;
    logic               in_ready, out_valid, out_ready;
    logic [2:0]         out_class;
    logic [8*AW_D2-1:0] out_logits;

    ids_cnn1d_engine u_engine (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_pending), .in_ready(in_ready), .in_data(in_buf),
        .out_valid(out_valid), .out_ready(out_ready),
        .out_class(out_class), .out_logits(out_logits)
    );

    // One-entry result buffer; the engine pipeline holds the rest.
    logic               res_valid;
    logic [2:0]         res_class;
    logic [8*AW_D2-1:0] res_logits;
    logic [31:0]        res_count;

    assign out_ready = !res_valid;
    wire   pop = avs_read && (avs_address == 5'd17) && res_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_pending <= 1'b0;
            res_valid  <= 1'b0;
            res_count  <= '0;
        end else begin
            if (in_pending && in_ready)                           in_pending <= 1'b0;
            if (avs_write && avs_address == 5'd16 && avs_writedata[0]) in_pending <= 1'b1;
            if (out_valid && out_ready) begin
                res_valid <= 1'b1;
                res_count <= res_count + 32'd1;
            end else if (pop) begin
                res_valid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (avs_write && avs_address < 5'd16)
            in_buf[32*avs_address[3:0] +: 32] <= avs_writedata;
        if (out_valid && out_ready) begin
            res_class  <= out_class;
            res_logits <= out_logits;
        end
    end

    always_ff @(posedge clk) begin
        if (avs_read) begin
            case (avs_address)
                5'd16:   avs_readdata <= {30'd0, res_valid, !in_pending};
                5'd17:   avs_readdata <= {res_valid, 27'd0, res_class != 3'd0, res_class};
                5'd26:   avs_readdata <= res_count;
                5'd27:   avs_readdata <= 32'h1D5C_0001;
                default: avs_readdata <= (avs_address >= 5'd18 && avs_address <= 5'd25)
                         ? 32'($signed(res_logits[AW_D2*(avs_address-5'd18) +: AW_D2]))
                         : 32'd0;
            endcase
        end
    end
endmodule
