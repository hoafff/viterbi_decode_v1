`timescale 1ns/1ps

// Top-level Viterbi decoder — rtl_v1 variant (further optimized P5).
// K = 3, R = 1/2, generator polynomials: 111 and 101.
// Input  : i_data[15:0] = eight received 2-bit symbols.
// Output : o_data[7:0]  = decoded 8-bit frame (low 2 bits are tail zeros).
//
// Architecture changes vs P5:
//   - Precompute_bmu (P3 reduced): 8-FF bank latches BMU_b outputs in phase A
//     so ACS_odd at phase B has a stable input. BMU_b chỉ chạy ở phase A
//     (active_a) → 0 dynamic power lãng phí ở phase B (cải tiến so với P5).
//   - Pipelined traceback (P-TB): 3-stage FF chain replaces the 7-level
//     combinational traceback.
//   - FSM extended from 10 to 13 states to add 3 traceback pipeline states.
//
// Latency from `en` pulse to `o_done`: 9 clock cycles (was 7 in P5, 6 in baseline).
// Output data is bit-for-bit equivalent to baseline for the same input.
module viterbi_decoder_v1 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] i_data,
    output wire [7:0]  o_data,
    output wire        o_done
);

    // =================================================================
    // Control signals (từ control_v1 — FSM 13 trạng thái)
    // =================================================================
    wire [3:0] state;
    wire       load_frame;
    wire       active;
    wire       active_a;
    wire       tb_enable;
    wire       output_cycle;

    control_v1 u_control (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .state        (state),
        .load_frame   (load_frame),
        .active       (active),
        .active_a     (active_a),
        .tb_enable    (tb_enable),
        .output_cycle (output_cycle)
    );

    // =================================================================
    // Memory bank signals (FF-bank trong memory_v1)
    // =================================================================
    wire [15:0] rx_reg;
    wire [1:0]  pm00, pm01, pm10, pm11;
    wire [3:0]  dec_s0, dec_s1, dec_s2, dec_s3, dec_s4, dec_s5;
    wire [1:0]  dec_s6;
    wire        dec_s7;
    wire [7:0]  tb_out;

    // pair_a, pair_b lấy thẳng từ rx_reg[15:14] và rx_reg[13:12] qua
    // extract_bit_v1 (combinational, dùng FF Q pin trực tiếp → không
    // cần thêm inverter).
    wire [1:0]  pair_a;
    wire [1:0]  pair_b;

    extract_bit_v1 u_extract_bit (
        .rx_reg (rx_reg),
        .pair_a (pair_a),
        .pair_b (pair_b)
    );

    // =================================================================
    // BMU outputs (combinational từ pair_a, pair_b)
    // =================================================================
    wire [1:0] bm_a00, bm_a11, bm_a10, bm_a01;
    wire [1:0] bm_b00, bm_b11, bm_b10, bm_b01;

    // BMU_a: operand-iso bằng active_a (gate output về 0 ở phase B để
    // tiết kiệm dynamic power; ACS_even ở phase A dùng combo bm_a*).
    branch_metric_v1 u_bmu_a (
        .rx_pair (pair_a),
        .active  (active_a),
        .bm00    (bm_a00),
        .bm11    (bm_a11),
        .bm10    (bm_a10),
        .bm01    (bm_a01)
    );

    // BMU_b: chỉ chạy ở phase A (active_a=1) vì precompute_bmu sẽ chốt
    // giá trị combo ở phase A vào FF, rồi ACS_odd ở phase B dùng reg_bm_b*
    // (không phải combo bm_b*). Ở phase B, active_a=0 → bm_b* = 0 (nhờ
    // operand-iso gate), precompute_bmu vẫn hold giá trị phase A → ACS_odd
    // vẫn dùng đúng. Tiết kiệm dynamic power của 4 cổng mux 2:1 + 4 adder
    // 1-bit của BMU_b trong 4 cycle phase B.
    branch_metric_v1 u_bmu_b (
        .rx_pair (pair_b),
        .active  (active_a),
        .bm00    (bm_b00),
        .bm11    (bm_b11),
        .bm10    (bm_b10),
        .bm01    (bm_b01)
    );

    // =================================================================
    // Precompute_bmu — 8 FF lưu bm_b* (chỉ BMU_b, vì chỉ cần cho ACS_odd)
    // =================================================================
    // Mục đích: Ở cycle ST_XB, ACS_odd cần `bm_b*` của cặp 2X+1 (cùng
    // cặp với pipereg_pm_mid từ cycle ST_XA). Tuy nhiên, pair_b ở
    // cycle ST_XB đã chuyển sang cặp 2X+3 (do rx_reg shift). Nếu
    // precompute_bmu không chốt giá trị cặp 2X+1 từ phase A, ACS_odd ở
    // phase B sẽ dùng sai cặp → kết quả sai. FF giữ giá trị cặp 2X+1
    // cho ACS_odd.
    //
    // Cách hoạt động: `we_pre = active_a` chốt ở phase A; ở phase B,
    // FF giữ giá trị cặp 2X+1 cho ACS_odd.
    wire [1:0] reg_bm_b00, reg_bm_b11, reg_bm_b10, reg_bm_b01;

    precompute_bmu u_pre_bmu (
        .clk         (clk),
        .rst_n       (rst_n),
        .we_pre      (active_a),  // chỉ update ở phase A

        .bm_b00      (bm_b00),
        .bm_b11      (bm_b11),
        .bm_b10      (bm_b10),
        .bm_b01      (bm_b01),

        .reg_bm_b00  (reg_bm_b00),
        .reg_bm_b11  (reg_bm_b11),
        .reg_bm_b10  (reg_bm_b10),
        .reg_bm_b01  (reg_bm_b01)
    );

    // =================================================================
    // ACS pipeline (cả ACS_even và ACS_odd dùng cùng module acs_csms;
    // pipereg_pm_mid ở giữa 2 stage; dec_even_latched là 1-stage FF từ
    // ACS_even decision)
    // =================================================================
    wire [1:0] pm_new00, pm_new01, pm_new10, pm_new11;
    wire [3:0] dec_odd;
    wire [3:0] dec_even_latched;

    wire we_pipereg  = load_frame | active;  // chốt pipereg_pm_mid
    wire we_dec_even = active_a;             // chỉ chốt ở phase A

    acs_pipeline_v1 u_acs_pipe (
        .clk             (clk),
        .rst_n           (rst_n),
        .we_pipereg      (we_pipereg),
        .we_dec_even     (we_dec_even),

        // BMU_a outputs (combo) — ACS_even dùng cùng phase A
        .reg_bm_a00      (bm_a00),
        .reg_bm_a11      (bm_a11),
        .reg_bm_a10      (bm_a10),
        .reg_bm_a01      (bm_a01),
        // BMU_b outputs (FF từ precompute_bmu) — ACS_odd dùng ở phase B
        .reg_bm_b00      (reg_bm_b00),
        .reg_bm_b11      (reg_bm_b11),
        .reg_bm_b10      (reg_bm_b10),
        .reg_bm_b01      (reg_bm_b01),

        // Current path metrics (combo từ memory_v1)
        .pm00            (pm00),
        .pm01            (pm01),
        .pm10            (pm10),
        .pm11            (pm11),

        // ACS_even_latched 1-stage FF output (ghi vào dec_s(2X) ở phase B)
        .dec_even_latched(dec_even_latched),

        // ACS_odd outputs (combo; registered in memory_v1 tại phase B)
        .pm_new00        (pm_new00),
        .pm_new01        (pm_new01),
        .pm_new10        (pm_new10),
        .pm_new11        (pm_new11),
        .dec_odd         (dec_odd)
    );

    // =================================================================
    // Pipelined traceback (P-TB 3-stage)
    // =================================================================
    traceback_pipelined u_traceback (
        .clk      (clk),
        .rst_n    (rst_n),
        .we_tb    (tb_enable),
        .dec_s1   (dec_s1),
        .dec_s2   (dec_s2),
        .dec_s3   (dec_s3),
        .dec_s4   (dec_s4),
        .dec_s5   (dec_s5),
        .dec_s6   (dec_s6),
        .dec_s7   (dec_s7),
        .tb_out   (tb_out)
    );

    // =================================================================
    // Memory bank
    // =================================================================
    memory_v1 u_memory (
        .clk              (clk),
        .rst_n            (rst_n),
        .load_frame       (load_frame),
        .active           (active),
        .output_cycle     (output_cycle),
        .state            (state),
        .i_data           (i_data),

        // ACS_odd + ACS_even_latched inputs
        .pm_new00         (pm_new00),
        .pm_new01         (pm_new01),
        .pm_new10         (pm_new10),
        .pm_new11         (pm_new11),
        .dec_odd          (dec_odd),
        .dec_even_latched (dec_even_latched),
        .tb_out           (tb_out),

        // Outputs (FF banks + o_data, o_done)
        .rx_reg           (rx_reg),
        .pm00             (pm00),
        .pm01             (pm01),
        .pm10             (pm10),
        .pm11             (pm11),
        .dec_s0           (dec_s0),
        .dec_s1           (dec_s1),
        .dec_s2           (dec_s2),
        .dec_s3           (dec_s3),
        .dec_s4           (dec_s4),
        .dec_s5           (dec_s5),
        .dec_s6           (dec_s6),
        .dec_s7           (dec_s7),
        .o_data           (o_data),
        .o_done           (o_done)
    );

endmodule
