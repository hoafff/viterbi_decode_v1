`timescale 1ns/1ps

// Precompute BMU output for ACS_odd (P3 reduced) — only stores bm_b*
// outputs into FF so ACS_odd at phase B has a stable input.
//
// Architecture:
//   * 4 metric outputs (bm00/11/10/01) for BMU_b. Each is 2-bit.
//   * Total: 4 metrics * 2 bits = 8 FF.
//   * Update is gated by `we_pre` = `active_a`:
//       - Ở phase A của mỗi cặp: chốt giá trị mới từ BMU_b combo.
//       - Ở phase B: giữ giá trị cặp hiện tại cho ACS_odd dùng.
//   * Lưu ý: KHÔNG cần chốt ở cycle load (cycle 0) vì pipereg_pm_mid ở
//     cycle 1 cũng = 0 (vô hại). reg_bm_b* = 0 sau reset là OK.
//
// Why this helps Fmax:
//   Trong P5, BMU_b bị gate bởi operand-iso ở phase B (active_a=0), làm
//   bm_b* = 0 ở phase B. Nếu để nguyên, ACS_odd ở phase B sẽ dùng bm_b* = 0
//   gây kết quả sai. Đó là lý do cần precompute_bmu.
//
//   Trong rtl_v1: BMU_b chỉ chạy ở phase A (active=active_a, giống BMU_a).
//   Ở cạnh clk cuối phase A, reg_bm_b* latches giá trị combo. Ở phase B,
//   BMU_b output = 0 (nhờ operand-iso gate) nhưng FF vẫn hold giá trị
//   phase A → ACS_odd dùng đúng. 0 dynamic power lãng phí ở phase B.
//
// Trade-off: +8 FF (4 metrics * 2 bit) so với baseline, nhưng cho phép
// phase B dùng FF-input thay vì combo-input → giảm critical path 1 mux.
//
// Critical path: rx_reg -> extract_bit (combo) -> BMU_b (combo) -> FF
// -> ACS_odd. FF ngay sau BMU_b output, nên ACS_odd input chỉ thấy
// 1 mux level (FF output), không phải combo.
module precompute_bmu (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we_pre,        // = active_a

    input  wire [1:0]  bm_b00, bm_b11, bm_b10, bm_b01,   // combo từ BMU_b

    output reg  [1:0]  reg_bm_b00, reg_bm_b11, reg_bm_b10, reg_bm_b01
);

    // 8 FF total for BMU_b (4 metrics * 2 bits)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_bm_b00 <= 2'b0;
            reg_bm_b11 <= 2'b0;
            reg_bm_b10 <= 2'b0;
            reg_bm_b01 <= 2'b0;
        end else if (we_pre) begin
            reg_bm_b00 <= bm_b00;
            reg_bm_b11 <= bm_b11;
            reg_bm_b10 <= bm_b10;
            reg_bm_b01 <= bm_b01;
        end
    end

endmodule
