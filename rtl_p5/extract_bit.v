`timescale 1ns/1ps

// Fixed-slice extractor for the rolling-rx_reg architecture.
module extract_bit (
    input  wire [2:0]  state,    // kept for interface stability; unused
    input  wire [15:0] rx_reg,
    output wire [1:0]  pair_a,
    output wire [1:0]  pair_b
);

    wire _unused_state = |state;

    assign pair_a = rx_reg[15:14];
    assign pair_b = rx_reg[13:12];

endmodule
