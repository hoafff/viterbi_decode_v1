`timescale 1ns/1ps

// Branch Metric Unit for K=3, R=1/2 Viterbi decoder.
// Generator outputs are one of: 00, 11, 10, 01.
// Metric = Hamming distance between received 2-bit symbol and expected symbol.
module branch_metric (
    input  wire [1:0] rx_pair,
    output wire [1:0] bm00,
    output wire [1:0] bm11,
    output wire [1:0] bm10,
    output wire [1:0] bm01
);

    assign bm00 = {1'b0,  rx_pair[1]} + {1'b0,  rx_pair[0]};
    assign bm11 = {1'b0, ~rx_pair[1]} + {1'b0, ~rx_pair[0]};
    assign bm10 = {1'b0, ~rx_pair[1]} + {1'b0,  rx_pair[0]};
    assign bm01 = {1'b0,  rx_pair[1]} + {1'b0, ~rx_pair[0]};

endmodule
