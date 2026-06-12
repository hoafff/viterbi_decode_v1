`timescale 1ns/1ps

// Add-Compare-Select for 4-state K=3 Viterbi decoder.
// Flat combinational ACS logic. Path metrics are 2-bit saturating.
// Semantic preserved from baseline: add -> saturate -> compare -> select.
module add_comp_slt (
    input  wire [1:0] bm00,
    input  wire [1:0] bm11,
    input  wire [1:0] bm10,
    input  wire [1:0] bm01,

    input  wire [1:0] pm00,
    input  wire [1:0] pm01,
    input  wire [1:0] pm10,
    input  wire [1:0] pm11,

    output wire [1:0] new_pm00,
    output wire [1:0] new_pm01,
    output wire [1:0] new_pm10,
    output wire [1:0] new_pm11,

    output wire [3:0] decision
);

    // next state 00: from 00 with output 00, from 01 with output 11
    wire [2:0] sum_00_a = {1'b0, pm00} + {1'b0, bm00};
    wire [2:0] sum_00_b = {1'b0, pm01} + {1'b0, bm11};
    wire [1:0] cand_00_a = sum_00_a[2] ? 2'b11 : sum_00_a[1:0];
    wire [1:0] cand_00_b = sum_00_b[2] ? 2'b11 : sum_00_b[1:0];

    // next state 01: from 10 with output 10, from 11 with output 01
    wire [2:0] sum_01_a = {1'b0, pm10} + {1'b0, bm10};
    wire [2:0] sum_01_b = {1'b0, pm11} + {1'b0, bm01};
    wire [1:0] cand_01_a = sum_01_a[2] ? 2'b11 : sum_01_a[1:0];
    wire [1:0] cand_01_b = sum_01_b[2] ? 2'b11 : sum_01_b[1:0];

    // next state 10: from 00 with output 11, from 01 with output 00
    wire [2:0] sum_10_a = {1'b0, pm00} + {1'b0, bm11};
    wire [2:0] sum_10_b = {1'b0, pm01} + {1'b0, bm00};
    wire [1:0] cand_10_a = sum_10_a[2] ? 2'b11 : sum_10_a[1:0];
    wire [1:0] cand_10_b = sum_10_b[2] ? 2'b11 : sum_10_b[1:0];

    // next state 11: from 10 with output 01, from 11 with output 10
    wire [2:0] sum_11_a = {1'b0, pm10} + {1'b0, bm01};
    wire [2:0] sum_11_b = {1'b0, pm11} + {1'b0, bm10};
    wire [1:0] cand_11_a = sum_11_a[2] ? 2'b11 : sum_11_a[1:0];
    wire [1:0] cand_11_b = sum_11_b[2] ? 2'b11 : sum_11_b[1:0];

    // Ties select candidate A to keep traceback deterministic.
    assign decision[0] = (cand_00_b < cand_00_a);
    assign decision[1] = (cand_01_b < cand_01_a);
    assign decision[2] = (cand_10_b < cand_10_a);
    assign decision[3] = (cand_11_b < cand_11_a);

    assign new_pm00 = decision[0] ? cand_00_b : cand_00_a;
    assign new_pm01 = decision[1] ? cand_01_b : cand_01_a;
    assign new_pm10 = decision[2] ? cand_10_b : cand_10_a;
    assign new_pm11 = decision[3] ? cand_11_b : cand_11_a;

endmodule


