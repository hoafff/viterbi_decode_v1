`timescale 1ns/1ps

// ACS pipeline wrapper for P5.
//
// Two ACS stages (ACS_even, ACS_odd) are separated by a pipeline register
// group. This halves the combinational depth between rx_reg/FF-bank and
// pm_reg/FF-bank, which is the dominant contributor to the baseline
// critical path (~19 levels).
//
// Latency is increased by 1 cycle (baseline 6 cycles -> P5 7 cycles):
//   cycle k     : ACS_even computes pm_mid (combinational from pm + bm_a)
//   cycle k+1   : pipereg_pm_mid latched, ACS_odd uses it together with bm_b
//                 to compute pm_new (combinational, registered next edge).
//
// `dec_even` is also latched (dec_even_latched) — chỉ chốt ở phase A
// (we_dec_even = active_a) để giữ giá trị ổn định xuyên suốt phase B, cho
// memory_p5 đủ thời gian ghi vào dec_s(even) ở phase A kế tiếp trước khi
// ACS_even mới ghi đè. Xem memory_p5.v để biết mapping enable chính xác.
module acs_pipeline_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we_pipereg,    // load_frame | active  (cho pipereg_pm_mid)
    input  wire        we_dec_even,   // chỉ high ở phase A (giữ dec_even qua phase B)

    input  wire [1:0]  bm_a00, bm_a11, bm_a10, bm_a01,
    input  wire [1:0]  bm_b00, bm_b11, bm_b10, bm_b01,

    input  wire [1:0]  pm00, pm01, pm10, pm11,

    output reg  [1:0]  pm_new00,
    output reg  [1:0]  pm_new01,
    output reg  [1:0]  pm_new10,
    output reg  [1:0]  pm_new11,

    output wire [3:0]  dec_odd,        // combo, registered by memory.p5 in phase B
    output reg  [3:0]  dec_even_latched // pipelined, sampled in phase A
);

    // -------------------- ACS_even (combinational) --------------------
    wire [1:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;
    wire [3:0] dec_even;

    acs_csms u_acs_even (
        .bm00    (bm_a00), .bm11 (bm_a11), .bm10 (bm_a10), .bm01 (bm_a01),
        .pm00    (pm00),   .pm01 (pm01),   .pm10 (pm10),   .pm11 (pm11),
        .new_pm00(pm_mid00), .new_pm01(pm_mid01),
        .new_pm10(pm_mid10), .new_pm11(pm_mid11),
        .decision(dec_even)
    );

    // -------------------- Pipeline register (P1) ---------------------
    // Hai always block tách biệt vì chúng có enable khác nhau:
    //   - pipereg_pm_mid ghi mỗi phase A và B (we_pipereg = load|active)
    //   - dec_even_latched CHỈ ghi ở phase A (we_dec_even) - giữ nguyên giá trị
    //     dec_even trong suốt phase B để memory_p5 có 1 cycle đầy đủ ở phase A
    //     tiếp theo để ghi vào dec_s(even) trước khi ACS_even mới ghi đè.
    reg [1:0] pipereg_pm_mid00, pipereg_pm_mid01;
    reg [1:0] pipereg_pm_mid10, pipereg_pm_mid11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipereg_pm_mid00 <= 2'b0;
            pipereg_pm_mid01 <= 2'b0;
            pipereg_pm_mid10 <= 2'b0;
            pipereg_pm_mid11 <= 2'b0;
        end else if (we_pipereg) begin
            pipereg_pm_mid00 <= pm_mid00;
            pipereg_pm_mid01 <= pm_mid01;
            pipereg_pm_mid10 <= pm_mid10;
            pipereg_pm_mid11 <= pm_mid11;
        end
    end

    // dec_even_latched: 1 tầng FF, chốt ở phase A.
    // Lý do KHÔNG dùng 2 tầng như bản cũ: nếu chốt pipereg_dec_even ở phase A
    // rồi chốt tiếp dec_even_latched ở phase B, giá trị ở dec_even_latched sẽ
    // lệch 1 cycle so với timing cần (memory_p5 muốn dec_even_latched = dec_even
    // của ACS_even phase A hiện tại, chứ không phải phase A trước).
    //
    // Tại đầu phase B cặp X, dec_even_latched đã có sẵn E_X (do cạnh clk
    // cuối phase A cặp X đã chốt). Cùng cạnh clk cuối phase B, memory_p5
    // ghi dec_s(2X) <- dec_even_latched (= E_X) và dec_s(2X+1) <- dec_odd
    // (= O_X). Mapping này match baseline.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_even_latched <= 4'b0;
        end else if (we_dec_even) begin
            dec_even_latched <= dec_even;
        end
    end

    // -------------------- ACS_odd (combinational) --------------------
    acs_csms u_acs_odd (
        .bm00    (bm_b00), .bm11 (bm_b11), .bm10 (bm_b10), .bm01 (bm_b01),
        .pm00    (pipereg_pm_mid00), .pm01 (pipereg_pm_mid01),
        .pm10    (pipereg_pm_mid10), .pm11 (pipereg_pm_mid11),
        .new_pm00(pm_new00), .new_pm01(pm_new01),
        .new_pm10(pm_new10), .new_pm11(pm_new11),
        .decision(dec_odd)
    );

endmodule
