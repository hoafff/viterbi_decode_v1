`timescale 1ns/1ps

// ACS pipeline wrapper for rtl_v1.
//
// Pipeline structure (between rx_reg/FF-bank and pm_reg/FF-bank):
//
//   cycle k     : ACS_even (acs_csms) computes pm_mid from pm + bm_a*
//                 (bm_a* là combo từ BMU_a, gate bởi active_a).
//   cycle k+1   : pipereg_pm_mid latched; ACS_odd (acs_csms) computes
//                 pm_new from pipereg_pm_mid + reg_bm_b* (FF từ
//                 precompute_bmu, lưu giá trị cặp X từ phase A).
//
//   dec_even_latched is registered in phase A (chỉ ghi 1 lần mỗi cặp)
//   dec_odd is combo from ACS_odd, registered by memory_v1 in phase B
module acs_pipeline_v1 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we_pipereg,    // load_frame | active (chốt pm_mid)
    input  wire        we_dec_even,   // chỉ high ở phase A (chốt dec_even)

    // BMU_a outputs (combo từ BMU_a, cho ACS_even dùng cùng phase A)
    input  wire [1:0]  reg_bm_a00, reg_bm_a11, reg_bm_a10, reg_bm_a01,
    // BMU_b outputs (FF từ precompute_bmu, cho ACS_odd dùng ở phase B)
    input  wire [1:0]  reg_bm_b00, reg_bm_b11, reg_bm_b10, reg_bm_b01,

    // Current path metrics
    input  wire [1:0]  pm00, pm01, pm10, pm11,

    // ACS_even -> pipereg_pm_mid stage 1 FF: 1-stage registered output
    // (combo ACS_even output được internal hook thẳng vào pipereg bên trong
    //  module này — không cần export ra ngoài).
    output reg  [3:0]  dec_even_latched,  // 1-stage FF output (registered)

    // ACS_odd outputs
    output wire [1:0]  pm_new00, pm_new01, pm_new10, pm_new11,
    output wire [3:0]  dec_odd        // ACS_odd decision (combo, registered in memory_v1)
);

    // -------------------- Internal combo signals --------------------
    // pm_mid* là output combo của ACS_even, nội bộ module dùng làm D-input
    // của pipereg_pm_mid. Không export ra ngoài vì không có consumer khác.
    wire [1:0] pm_mid00, pm_mid01, pm_mid10, pm_mid11;
    wire [3:0] dec_even;

    // -------------------- ACS_even (combinational) --------------------
    // Uses acs_csms (CSMS compare-select-min, OR-saturate). acs_even và
    // acs_odd dùng cùng module vì không có lợi ích thực tế nào khi viết
    // 2 phiên bản: synthesis tool sẽ tạo cùng netlist cho cùng 1 logic.
    acs_csms u_acs_even (
        .bm00    (reg_bm_a00), .bm11 (reg_bm_a11),
        .bm10    (reg_bm_a10), .bm01 (reg_bm_a01),
        .pm00    (pm00),   .pm01 (pm01),
        .pm10    (pm10),   .pm11 (pm11),
        .new_pm00(pm_mid00), .new_pm01(pm_mid01),
        .new_pm10(pm_mid10), .new_pm11(pm_mid11),
        .decision(dec_even)
    );

    // -------------------- Pipeline register (P1) ---------------------
    // 4 FF for pipereg_pm_mid, gated by we_pipereg.
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

    // -------------------- ACS_odd (combinational) --------------------
    // Uses acs_csms. ACS_odd isolated from rx_reg timing by the pipereg
    // (pm_mid* are FF outputs, not combo from rx_reg/BMU).
    acs_csms u_acs_odd (
        .bm00    (reg_bm_b00), .bm11 (reg_bm_b11),
        .bm10    (reg_bm_b10), .bm01 (reg_bm_b01),
        .pm00    (pipereg_pm_mid00), .pm01 (pipereg_pm_mid01),
        .pm10    (pipereg_pm_mid10), .pm11 (pipereg_pm_mid11),
        .new_pm00(pm_new00), .new_pm01(pm_new01),
        .new_pm10(pm_new10), .new_pm11(pm_new11),
        .decision(dec_odd)
    );

    // -------------------- dec_even_latched FF -----------------------
    // 1-stage FF, chốt ở phase A. Output goes to memory_v1 which writes
    // it into dec_s(2X) at the end of phase B of the same cycle.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_even_latched <= 4'b0;
        end else if (we_dec_even) begin
            dec_even_latched <= dec_even;
        end
    end

endmodule

