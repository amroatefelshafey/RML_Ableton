// ============================================================================
// Avalon-MM slave that connects ids_cnn1d_engine to the HPS on the DE1-SoC.
//
// Connect s0 to hps_0.h2f_axi_master (the full HPS-to-FPGA bridge, HPS base
// 0xC000_0000). That bridge hangs off the L3 main switch; the lightweight
// bridge goes through the slower L4 peripheral switch, so MMIO reads here
// return sooner. Reads have no side effects and use a fixed read latency of
// one cycle, with no wait states.
//
// The whole result fits in one 32-bit word, so the HPS gets it with a single
// bridge read: poll RESULT until SEQ changes.
//
// Word  Byte   R/W  Register
// 0     0x00   R    RESULT  [2:0]   class (0 = BENIGN)
//                           [3]     attack (class != 0)
//                           [4]     valid: RESULT/LOGIT hold the latest start
//                           [5]     busy: engine running
//                           [6]     pending: a start is queued; do not
//                                   write FEAT until it clears
//                           [15:8]  latency in cycles (29)
//                           [31:16] SEQ, +1 per finished inference
// 1     0x04   W    CTRL    [0] START (write 1, self-clearing)
//                           [1] AUTOSTART: writing byte 3 of FEAT[15]
//                               starts the engine (default on)
//                           [2] IRQ_EN
//              R            [1] AUTOSTART, [2] IRQ_EN
// 2     0x08   R/W1C IRQ    [0] done pending; write 1 to clear
// 3     0x0C   R    ID      0x1D5C_0002
// 8-15  0x20   R    LOGIT[0..7]  signed logits x512, sign-extended
// 16-31 0x40   R/W  FEAT[0..15]  features 4w..4w+3, feature 4w in [7:0]
//                                (same byte order as an int8_t[64] array)
//
// The engine copies FEAT when it starts, so once pending clears the HPS can
// write the next sample while the current one is still computing. RESULT
// holds one result, so collect it before the next one finishes.
// ============================================================================
module ids_cnn1d_hps_avmm (
    input  logic        clk,
    input  logic        rst_n,

    // Avalon-MM slave s0 (word addressing, readLatency = 1)
    input  logic [4:0]  avs_address,
    input  logic        avs_read,
    input  logic        avs_write,
    input  logic [31:0] avs_writedata,
    input  logic [3:0]  avs_byteenable,
    output logic [31:0] avs_readdata,

    // Interrupt sender (to hps_0.f2h_irq0)
    output logic        irq,

    // Conduit for board LEDs / HEX displays
    output logic [2:0]  coe_class,
    output logic        coe_attack,
    output logic        coe_busy,
    output logic        coe_valid
);

    localparam logic [31:0] ID = 32'h1D5C_0002;

    localparam logic [4:0] A_RESULT = 5'd0,
                           A_CTRL   = 5'd1,
                           A_IRQ    = 5'd2,
                           A_ID     = 5'd3;

    // ------------------------------------------------------------------------
    // Engine
    // ------------------------------------------------------------------------
    logic signed [7:0]  feat [0:63];
    logic               eng_start, eng_busy, eng_done, eng_attack;
    logic [2:0]         eng_class;
    logic [15:0]        eng_latency;
    logic signed [20:0] eng_logits [0:7];

    ids_cnn1d_engine u_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (eng_start),
        .input_features (feat),
        .busy           (eng_busy),
        .done           (eng_done),
        .pred_class     (eng_class),
        .is_attack      (eng_attack),
        .latency_cycles (eng_latency),
        .debug_logits   (eng_logits)
    );

    // ------------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------------
    logic               autostart, irq_en, irq_pending;
    logic               pending, res_valid;
    logic [2:0]         res_class;
    logic               res_attack;
    logic [7:0]         res_latency;
    logic [15:0]        res_seq;
    logic signed [20:0] res_logits [0:7];

    wire wr_ctrl   = avs_write && avs_address == A_CTRL;
    wire wr_feat   = avs_write && avs_address[4];
    wire start_wr = (wr_ctrl && avs_byteenable[0] && avs_writedata[0]) ||
                    (autostart && wr_feat && avs_address[3:0] == 4'd15 && avs_byteenable[3]);

    // Registered so the engine sees the FEAT[15] write that triggered it:
    // the engine copies feat[] on the same edge that start is high.
    logic start_req;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) start_req <= 1'b0;
        else        start_req <= start_wr;
    end

    // The engine only accepts start while idle (busy low), so hold a request
    // that arrives during an inference until it finishes.
    wire go = pending || start_req;
    assign eng_start = go && !eng_busy;

    // Feature buffer, written byte by byte so any access width works
    always_ff @(posedge clk) begin
        if (wr_feat) begin
            for (int b = 0; b < 4; b++)
                if (avs_byteenable[b])
                    feat[4 * avs_address[3:0] + b] <= avs_writedata[8*b +: 8];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            autostart   <= 1'b1;
            irq_en      <= 1'b0;
            irq_pending <= 1'b0;
            pending     <= 1'b0;
            res_valid   <= 1'b0;
            res_class   <= 3'd0;
            res_attack  <= 1'b0;
            res_latency <= 8'd0;
            res_seq     <= 16'd0;
        end else begin
            pending <= go && eng_busy;

            if (wr_ctrl && avs_byteenable[0]) begin
                autostart <= avs_writedata[1];
                irq_en    <= avs_writedata[2];
            end

            if (eng_done) begin
                res_class   <= eng_class;
                res_attack  <= eng_attack;
                res_latency <= eng_latency[7:0];
                res_seq     <= res_seq + 16'd1;
                irq_pending <= 1'b1;
            end
            if (avs_write && avs_address == A_IRQ && avs_byteenable[0] && avs_writedata[0])
                irq_pending <= 1'b0;

            // done arrives while the engine is idle, so a queued start can be
            // accepted in the same cycle; the new start wins.
            if (eng_start)     res_valid <= 1'b0;
            else if (eng_done) res_valid <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (eng_done) res_logits <= eng_logits;
    end

    // ------------------------------------------------------------------------
    // Read mux (registered: readLatency = 1)
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (avs_read) begin
            if (avs_address[4]) begin
                avs_readdata <= {feat[4*avs_address[3:0] + 3], feat[4*avs_address[3:0] + 2],
                                 feat[4*avs_address[3:0] + 1], feat[4*avs_address[3:0]]};
            end else if (avs_address[3]) begin
                avs_readdata <= 32'(res_logits[avs_address[2:0]]);
            end else begin
                case (avs_address)
                    A_RESULT: avs_readdata <= {res_seq, res_latency, 1'b0, pending, eng_busy,
                                               res_valid, res_attack, res_class};
                    A_CTRL:   avs_readdata <= {29'd0, irq_en, autostart, 1'b0};
                    A_IRQ:    avs_readdata <= {31'd0, irq_pending};
                    A_ID:     avs_readdata <= ID;
                    default:  avs_readdata <= 32'd0;
                endcase
            end
        end
    end

    assign irq        = irq_en && irq_pending;
    assign coe_class  = res_class;
    assign coe_attack = res_attack;
    assign coe_busy   = eng_busy;
    assign coe_valid  = res_valid;

endmodule
