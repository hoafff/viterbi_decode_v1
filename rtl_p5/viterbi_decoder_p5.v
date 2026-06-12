`timescale 1ns/1ps

// Top-level Viterbi decoder — P5 hybrid high-speed variant.
// K = 3, R = 1/2, generator polynomials: 111 and 101.
// Input  : i_data[15:0] = eight received 2-bit symbols.
// Output : o_data[7:0]  = decoded 8-bit frame (low 2 bits are tail zeros).
//
// Architecture changes vs baseline:
//   - FSM has 10 states (6 -> 10) with phase A / phase B per ACS cycle.
//   - ACS_even and ACS_odd are now separated by a pipeline register
//     (acs_pipeline_p5), which roughly halves the critical path.
//   - ACS butterflies are re-implemented with OR-saturate and CSMS
//     compare-select (acs_csms) for shorter compare-select depth.
//   - Branch metric units have an `active` operand-isolation input
//     (branch_metric_p5) so the BMU/ACS tree is quiet outside phase A.
//   - The `state` port of extract_bit is removed (extract_bit_p5).
//   - memory_p5 writes dec_s* in two phases (odd/even) instead of one.
//
// Latency from `en` pulse to `o_done`: 7 clock cycles (was 6).
// Output data is bit-for-bit equivalent to baseline for the same input.
module viterbi_decoder_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] i_data,
    output wire [7:0]  o_data,
    output wire        o_done
);

    wire [3:0] state;
    wire       load_frame;
    wire       active;
    wire       active_a;
    wire       output_cycle;

    control_p5 u_control (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .state        (state),
        .load_frame   (load_frame),
        .active       (active),
        .active_a     (active_a),
        .output_cycle (output_cycle)
    );

    wire [15:0] rx_reg;
    wire [1:0]  pm00, pm01, pm10, pm11;
    wire [3:0]  dec_s0, dec_s1, dec_s2, dec_s3, dec_s4, dec_s5;
    wire [1:0]  dec_s6;
    wire        dec_s7;
    wire [7:0]  tb_out;
    wire [1:0]  pair_a, pair_b;

    extract_bit_p5 u_extract_bit (
        .rx_reg (rx_reg),
        .pair_a (pair_a),
        .pair_b (pair_b)
    );

    wire [1:0] bm_a00, bm_a11, bm_a10, bm_a01;
    wire [1:0] bm_b00, bm_b11, bm_b10, bm_b01;

    branch_metric_p5 u_bmu_a (
        .rx_pair (pair_a),
        .active  (active_a),
        .bm00    (bm_a00), .bm11 (bm_a11), .bm10 (bm_a10), .bm01 (bm_a01)
    );

    branch_metric_p5 u_bmu_b (
        .rx_pair (pair_b),
        .active  (active_a),
        .bm00    (bm_b00), .bm11 (bm_b11), .bm10 (bm_b10), .bm01 (bm_b01)
    );

    wire [1:0] pm_new00, pm_new01, pm_new10, pm_new11;
    wire [3:0] dec_odd;
    wire [3:0] dec_even_latched;
    wire       we_pipereg = load_frame | active;
    // dec_even_latched chỉ chốt ở phase A: tại cuối phase A cặp X, dec_even
    // (E_X) được chốt vào dec_even_latched. Tại phase B cặp X, memory_p5
    // ghi dec_s(2X) <- dec_even_latched (= E_X) cùng lúc với ghi dec_s(2X+1)
    // <- dec_odd (= O_X). Mapping này match baseline (cùng state ST_X chốt
    // cả E_X và O_X).
    wire       we_dec_even = active_a;

    acs_pipeline_p5 u_acs_pipe (
        .clk              (clk),
        .rst_n            (rst_n),
        .we_pipereg       (we_pipereg),
        .we_dec_even      (we_dec_even),
        .bm_a00 (bm_a00), .bm_a11 (bm_a11), .bm_a10 (bm_a10), .bm_a01 (bm_a01),
        .bm_b00 (bm_b00), .bm_b11 (bm_b11), .bm_b10 (bm_b10), .bm_b01 (bm_b01),
        .pm00 (pm00), .pm01 (pm01), .pm10 (pm10), .pm11 (pm11),
        .pm_new00 (pm_new00), .pm_new01 (pm_new01),
        .pm_new10 (pm_new10), .pm_new11 (pm_new11),
        .dec_odd         (dec_odd),
        .dec_even_latched(dec_even_latched)
    );

    traceback u_traceback (
        .dec_s0       (dec_s0), .dec_s1 (dec_s1),
        .dec_s2       (dec_s2), .dec_s3 (dec_s3),
        .dec_s4       (dec_s4), .dec_s5 (dec_s5),
        .dec_s6       (dec_s6), .dec_s7 (dec_s7),
        .decoded_data (tb_out)
    );

    memory_p5 u_memory (
        .clk              (clk),
        .rst_n            (rst_n),
        .load_frame       (load_frame),
        .active           (active),
        .output_cycle     (output_cycle),
        .state            (state),
        .i_data           (i_data),
        .pm_new00         (pm_new00), .pm_new01 (pm_new01),
        .pm_new10         (pm_new10), .pm_new11 (pm_new11),
        .dec_odd          (dec_odd),
        .dec_even_latched (dec_even_latched),
        .tb_out           (tb_out),
        .rx_reg           (rx_reg),
        .pm00 (pm00), .pm01 (pm01), .pm10 (pm10), .pm11 (pm11),
        .dec_s0 (dec_s0), .dec_s1 (dec_s1), .dec_s2 (dec_s2), .dec_s3 (dec_s3),
        .dec_s4 (dec_s4), .dec_s5 (dec_s5), .dec_s6 (dec_s6), .dec_s7 (dec_s7),
        .o_data (o_data), .o_done (o_done)
    );

endmodule
