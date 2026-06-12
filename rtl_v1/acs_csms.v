`timescale 1ns/1ps

// Add-Compare-Select for 4-state K=3 Viterbi decoder — P5 variant.
//
// Two speed-ups vs baseline add_comp_slt.v:
//   1) OR-saturate:  cand = sum[1:0] | {2{sum[2]}}
//      saves one level of logic vs the `?:` 3-to-1 mux.
//   2) CSMS compare-select: instead of `decision = (cand_b < cand_a)` plus
//      a 2:1 mux, the comparison is reduced to two gates:
//        lt_msb = cand_b[1] & ~cand_a[1]                 (1 AOI/AND gate)
//        lt_lsb = ~lt_msb & cand_b[0] & ~cand_a[0]       (2 AOI/AND gates)
//        sel    = lt_msb | lt_lsb                        (1 OR gate)
//      and the select mux is unchanged. Net saving: ~3 logic levels per
//      butterfly. Ties still select candidate A because lt_msb=lt_lsb=0
//      when cand_b == cand_a.
//
// Algorithm equivalence to baseline is preserved bit-for-bit because
//   (a < b)  <->  b[1] < a[1]  OR  (b[1] == a[1] AND b[0] < a[0])
//   (b[0] < a[0])  <->  b[0] == 1 AND a[0] == 0  (for 1-bit operands).
// `lt_msb | lt_lsb` is the standard "B strictly less than A" predicate.
module acs_csms (
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

    // ---------------- butterfly 00 : (pm00+bm00) vs (pm01+bm11) ----------------
    wire [2:0] s00a = {1'b0, pm00} + {1'b0, bm00};
    wire [2:0] s00b = {1'b0, pm01} + {1'b0, bm11};
    wire [1:0] c00a = s00a[1:0] | {2{s00a[2]}};
    wire [1:0] c00b = s00b[1:0] | {2{s00b[2]}};
    wire lt00_msb = c00b[1] & ~c00a[1];
    wire lt00_lsb = ~lt00_msb & c00b[0] & ~c00a[0];
    wire sel00    = lt00_msb | lt00_lsb;
    assign decision[0] = sel00;
    assign new_pm00    = sel00 ? c00b : c00a;

    // ---------------- butterfly 01 : (pm10+bm10) vs (pm11+bm01) ----------------
    wire [2:0] s01a = {1'b0, pm10} + {1'b0, bm10};
    wire [2:0] s01b = {1'b0, pm11} + {1'b0, bm01};
    wire [1:0] c01a = s01a[1:0] | {2{s01a[2]}};
    wire [1:0] c01b = s01b[1:0] | {2{s01b[2]}};
    wire lt01_msb = c01b[1] & ~c01a[1];
    wire lt01_lsb = ~lt01_msb & c01b[0] & ~c01a[0];
    wire sel01    = lt01_msb | lt01_lsb;
    assign decision[1] = sel01;
    assign new_pm01    = sel01 ? c01b : c01a;

    // ---------------- butterfly 10 : (pm00+bm11) vs (pm01+bm00) ----------------
    wire [2:0] s10a = {1'b0, pm00} + {1'b0, bm11};
    wire [2:0] s10b = {1'b0, pm01} + {1'b0, bm00};
    wire [1:0] c10a = s10a[1:0] | {2{s10a[2]}};
    wire [1:0] c10b = s10b[1:0] | {2{s10b[2]}};
    wire lt10_msb = c10b[1] & ~c10a[1];
    wire lt10_lsb = ~lt10_msb & c10b[0] & ~c10a[0];
    wire sel10    = lt10_msb | lt10_lsb;
    assign decision[2] = sel10;
    assign new_pm10    = sel10 ? c10b : c10a;

    // ---------------- butterfly 11 : (pm10+bm01) vs (pm11+bm10) ----------------
    wire [2:0] s11a = {1'b0, pm10} + {1'b0, bm01};
    wire [2:0] s11b = {1'b0, pm11} + {1'b0, bm10};
    wire [1:0] c11a = s11a[1:0] | {2{s11a[2]}};
    wire [1:0] c11b = s11b[1:0] | {2{s11b[2]}};
    wire lt11_msb = c11b[1] & ~c11a[1];
    wire lt11_lsb = ~lt11_msb & c11b[0] & ~c11a[0];
    wire sel11    = lt11_msb | lt11_lsb;
    assign decision[3] = sel11;
    assign new_pm11    = sel11 ? c11b : c11a;

endmodule
