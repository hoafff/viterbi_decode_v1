`timescale 1ns/1ps

// Branch Metric Unit for K=3, R=1/2 Viterbi decoder — P5 variant.
// Adds operand-isolation: when `active=0`, rx_pair is forced to 2'b00 so
// the BMU/ACS combinational tree settles to a constant, reducing glitch
// and dynamic power in IDLE / ST_OUT / phase-B cycles.
//
// Lưu ý: Ở top-level, port `active` của BMU được nối với tín hiệu
// `active_a` của control_p5 (chỉ high ở phase A). Lý do: ACS_odd chạy
// ở phase B nhưng dùng pipereg_pm_mid (đã chốt từ phase A trước) —
// giá trị ACS_even cũ không cần cập nhật ở phase B, nên có thể gate
// input BMU về 0 để tiết kiệm switching power.
//
// Generator outputs are one of: 00, 11, 10, 01.
// Metric = Hamming distance between received 2-bit symbol and expected.
module branch_metric_p5 (
    input  wire [1:0] rx_pair,
    input  wire       active,    // 1 during ST_*A cycles (phase A of pipeline)
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
