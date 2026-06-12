`timescale 1ns/1ps

// Branch Metric Unit for K=3, R=1/2 Viterbi decoder — rtl_v1 variant.
// Same as branch_metric_p5.v with operand-isolation by `active`.
//
// Ở rtl_v1, port `active` của BMU_a được nối với `bmu_active` (high ở
// cycle load + phase A), còn BMU_b được nối với `1'b1` (luôn chạy) vì
// precompute_bmu cần giá trị combo liên tục từ BMU_b.
//
// Generator outputs are one of: 00, 11, 10, 01.
// Metric = Hamming distance between received 2-bit symbol and expected.
module branch_metric_v1 (
    input  wire [1:0] rx_pair,
    input  wire       active,    // 1 cho phép BMU chạy; 0 gate output về 0
    output wire [1:0] bm00,
    output wire [1:0] bm11,
    output wire [1:0] bm10,
    output wire [1:0] bm01
);

    wire [1:0] rx_g = active ? rx_pair : 2'b00;

    assign bm00 = {1'b0,  rx_g[1]} + {1'b0,  rx_g[0]};
    assign bm11 = {1'b0, ~rx_g[1]} + {1'b0, ~rx_g[0]};
    assign bm10 = {1'b0, ~rx_g[1]} + {1'b0,  rx_g[0]};
    assign bm01 = {1'b0,  rx_g[1]} + {1'b0, ~rx_g[0]};

endmodule

