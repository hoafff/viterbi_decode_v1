`timescale 1ns/1ps

// Top-level Viterbi decoder.
// K = 3, R = 1/2, generator polynomials: 111 and 101.
// Input  : i_data[15:0] = eight received 2-bit symbols.
// Output : o_data[7:0]  = decoded 8-bit frame (low 2 bits are tail zeros).
module viterbi_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] i_data,
    output wire [7:0]  o_data,
    output wire        o_done
);

    wire [2:0] state;
    wire       load_frame;
    wire       active;
    wire       output_cycle;

    control u_control (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .state        (state),
        .load_frame   (load_frame),
        .active       (active),
        .output_cycle (output_cycle)
    );

    wire [15:0] rx_reg;
    wire [1:0]  pm00, pm01, pm10, pm11;
    wire [3:0]  dec_s0, dec_s1, dec_s2, dec_s3, dec_s4, dec_s5;
    wire [1:0]  dec_s6;
    wire        dec_s7;

    wire [1:0] pair_a, pair_b;

    extract_bit u_extract_bit (
        .state  (state),
        .rx_reg (rx_reg),
        .pair_a (pair_a),
        .pair_b (pair_b)
    );

    wire [1:0] bm_a00, bm_a11, bm_a10, bm_a01;
    wire [1:0] bm_b00, bm_b11, bm_b10, bm_b01;

    branch_metric u_bmu_a (
        .rx_pair (pair_a),
        .bm00    (bm_a00), .bm11 (bm_a11), .bm10 (bm_a10), .bm01 (bm_a01)
    );

    branch_metric u_bmu_b (
        .rx_pair (pair_b),
        .bm00    (bm_b00), .bm11 (bm_b11), .bm10 (bm_b10), .bm01 (bm_b01)
    );

    wire [1:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;
    wire [3:0] dec_even;

    add_comp_slt u_acs_even (
        .bm00     (bm_a00), .bm11 (bm_a11), .bm10 (bm_a10), .bm01 (bm_a01),
        .pm00     (pm00),   .pm01 (pm01),   .pm10 (pm10),   .pm11 (pm11),
        .new_pm00 (pm_mid00), .new_pm01 (pm_mid01),
        .new_pm10 (pm_mid10), .new_pm11 (pm_mid11),
        .decision (dec_even)
    );

    wire [1:0] pm_new00, pm_new01, pm_new10, pm_new11;
    wire [3:0] dec_odd;

    add_comp_slt u_acs_odd (
        .bm00     (bm_b00), .bm11 (bm_b11), .bm10 (bm_b10), .bm01 (bm_b01),
        .pm00     (pm_mid00), .pm01 (pm_mid01),
        .pm10     (pm_mid10), .pm11 (pm_mid11),
        .new_pm00 (pm_new00), .new_pm01 (pm_new01),
        .new_pm10 (pm_new10), .new_pm11 (pm_new11),
        .decision (dec_odd)
    );

    wire [7:0] tb_out;

    traceback u_traceback (
        .dec_s0       (dec_s0), .dec_s1 (dec_s1),
        .dec_s2       (dec_s2), .dec_s3 (dec_s3),
        .dec_s4       (dec_s4), .dec_s5 (dec_s5),
        .dec_s6       (dec_s6), .dec_s7 (dec_s7),
        .decoded_data (tb_out)
    );

    memory u_memory (
        .clk          (clk), .rst_n (rst_n),
        .load_frame   (load_frame), .active (active),
        .output_cycle (output_cycle), .state (state),
        .i_data       (i_data),
        .pm_new00     (pm_new00), .pm_new01 (pm_new01),
        .pm_new10     (pm_new10), .pm_new11 (pm_new11),
        .dec_even     (dec_even), .dec_odd (dec_odd),
        .tb_out       (tb_out), .rx_reg (rx_reg),
        .pm00         (pm00), .pm01 (pm01), .pm10 (pm10), .pm11 (pm11),
        .dec_s0       (dec_s0), .dec_s1 (dec_s1), .dec_s2 (dec_s2), .dec_s3 (dec_s3),
        .dec_s4       (dec_s4), .dec_s5 (dec_s5), .dec_s6 (dec_s6), .dec_s7 (dec_s7),
        .o_data       (o_data), .o_done (o_done)
    );

endmodule
