// ============================================================================
// Balanced combinational adder tree.
// Sums N signed W-bit terms packed into `terms` (term i at [i*W +: W]).
// Leaves are padded to a power of two with zeros; constant-zero leaves (zero
// weights) are pruned by synthesis, so only the real terms cost adders.
// The caller must size W so the full sum cannot overflow.
// ============================================================================
module adder_tree #(
    parameter int N = 8,
    parameter int W = 16
) (
    input  logic [N*W-1:0]       terms,
    output logic signed [W-1:0]  sum
);
    localparam int L = (N > 1) ? $clog2(N) : 0;
    localparam int M = 1 << L;

    // Heap layout: node i has children 2i+1 and 2i+2; leaves at [M-1, 2M-2].
    logic signed [W-1:0] node [0:2*M-2];

    always_comb begin
        for (int i = 0; i < M; i++)
            node[M-1+i] = (i < N) ? $signed(terms[i*W +: W]) : '0;
        for (int i = M-2; i >= 0; i--)
            node[i] = node[2*i+1] + node[2*i+2];
    end

    assign sum = node[0];
endmodule
