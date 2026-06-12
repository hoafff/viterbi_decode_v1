`timescale 1ns/1ps

// P5/r1 variant of extract_bit — same logic as baseline (fixed-slice on
// rx_reg[15:12]), but the unused `state` port is removed. The pair
// signals come straight from the Q output of rx_reg, so synthesis can
// use the FF's Q pin directly and avoid an extra inverter stage.
module extract_bit_v1 (
    input  wire [15:0] rx_reg,
    output wire [1:0]  pair_a,
    output wire [1:0]  pair_b
);

    assign pair_a = rx_reg[15:14];
    assign pair_b = rx_reg[13:12];

endmodule
