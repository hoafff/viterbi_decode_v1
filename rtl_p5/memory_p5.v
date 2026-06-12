`timescale 1ns/1ps

// Register bank for the Viterbi decoder — P5 variant.
//
// Differences vs baseline memory.v:
//   - `state` port is [3:0] (was [2:0]) because P5 has 10 FSM states.
//   - New input `dec_even_latched[3:0]`: pipelined dec_even from
//     acs_pipeline_p5, written into the "even" dec_s* banks.
//   - dec_s* writes theo phase B của cặp tương ứng (giống baseline về timing):
//       dec_s(2X)   <- dec_even_latched  (E_X, đã chốt cuối phase A cặp X)
//       dec_s(2X+1) <- dec_odd            (O_X, ACS_odd combo ở phase B cặp X)
//     This preserves the baseline's semantics: at the end of the frame,
//     dec_s0..dec_s7 hold the per-cycle decisions in time order so
//     traceback.v produces the same decoded_data as baseline (with +1
//     cycle of latency).
//   - o_data / o_done unchanged.
//
// Enable groups:
//   1) rx_reg              -> load_frame | active
//   2) path metrics        -> we_pm     = load_frame | active
//   3) dec_s0              -> we_d01_even = (state == ST_01B)   (ghi dec_even_latched[3:0] - E_0)
//   4) dec_s1              -> we_d01_odd  = (state == ST_01B)   (ghi dec_odd - O_0)
//   5) dec_s2              -> we_d23_even = (state == ST_23B)   (E_1)
//   6) dec_s3              -> we_d23_odd  = (state == ST_23B)   (O_1)
//   7) dec_s4              -> we_d45_even = (state == ST_45B)   (E_2)
//   8) dec_s5              -> we_d45_odd  = (state == ST_45B)   (O_2)
//   9) dec_s6              -> we_d67_even = (state == ST_67B)   (E_3[1:0])
//  10) dec_s7              -> we_d67_odd  = (state == ST_67B)   (O_3[0])
//  11) o_data             -> we_out    = output_cycle
//      o_done             -> free-running (not enable-gated)
//
// Lý do mapping: tại cuối phase A của cặp X, ACS_even vừa tính xong E_X
// và dec_even_latched chốt E_X. Tại phase B của cặp X, dec_even_latched
// đã có sẵn E_X, đồng thời ACS_odd vừa tính xong O_X. Cả hai được ghi
// vào dec_s(2X) và dec_s(2X+1) tại cạnh clk kết thúc phase B - GIỐNG
// baseline (1 cycle chốt cả E_X và O_X tại cùng state ST_X).
//
// Lưu ý quan trọng: thứ tự BIT trong {E_3[1:0], E_2, E_1, E_0, O_3, O_2,
// O_1, O_0} phải match với baseline để traceback (giả sử state 00 ở cuối)
// ra cùng kết quả. Traceback.v đọc theo thứ tự dec_s7, dec_s6, ..., dec_s1
// (bỏ dec_s0). Vậy dec_s7 cần chứa O_3[0] (gần encoder nhất) - đúng với
// mapping trên.
module memory_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_frame,
    input  wire        active,
    input  wire        output_cycle,
    input  wire [3:0]  state,
    input  wire [15:0] i_data,

    input  wire [1:0]  pm_new00,
    input  wire [1:0]  pm_new01,
    input  wire [1:0]  pm_new10,
    input  wire [1:0]  pm_new11,
    input  wire [3:0]  dec_odd,
    input  wire [3:0]  dec_even_latched,
    input  wire [7:0]  tb_out,

    output reg  [15:0] rx_reg,
    output reg  [1:0]  pm00,
    output reg  [1:0]  pm01,
    output reg  [1:0]  pm10,
    output reg  [1:0]  pm11,
    output reg  [3:0]  dec_s0,
    output reg  [3:0]  dec_s1,
    output reg  [3:0]  dec_s2,
    output reg  [3:0]  dec_s3,
    output reg  [3:0]  dec_s4,
    output reg  [3:0]  dec_s5,
    output reg  [1:0]  dec_s6,
    output reg         dec_s7,
    output reg  [7:0]  o_data,
    output reg         o_done
);

    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_01A  = 4'd1, ST_01B = 4'd2;
    localparam [3:0] ST_23A  = 4'd3, ST_23B = 4'd4;
    localparam [3:0] ST_45A  = 4'd5, ST_45B = 4'd6;
    localparam [3:0] ST_67A  = 4'd7, ST_67B = 4'd8;
    localparam [3:0] ST_OUT  = 4'd9;

    wire we_pm       = load_frame | active;
    // Tất cả 8 bank được ghi tại phase B của cặp tương ứng (giống baseline).
    // dec_s(2X)   <- dec_even_latched (E_X đã được ACS_even sinh ra ở phase A)
    // dec_s(2X+1) <- dec_odd          (O_X được ACS_odd sinh ra ở phase B)
    wire we_d01_even = (state == ST_01B);
    wire we_d01_odd  = (state == ST_01B);
    wire we_d23_even = (state == ST_23B);
    wire we_d23_odd  = (state == ST_23B);
    wire we_d45_even = (state == ST_45B);
    wire we_d45_odd  = (state == ST_45B);
    wire we_d67_even = (state == ST_67B);
    wire we_d67_odd  = (state == ST_67B);
    wire we_out      = output_cycle;

    // ------------------------------------------------------------------
    // 1) rx_reg : shift-by-4 register (unchanged from baseline)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_reg <= 16'b0;
        end else if (load_frame) begin
            rx_reg <= i_data;
        end else if (active) begin
            rx_reg <= {rx_reg[11:0], 4'b0};
        end
    end

    // ------------------------------------------------------------------
    // 2) path metrics (unchanged from baseline)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pm00 <= 2'd0;
            pm01 <= 2'd3;
            pm10 <= 2'd3;
            pm11 <= 2'd3;
        end else if (we_pm) begin
            if (load_frame) begin
                pm00 <= 2'd0;
                pm01 <= 2'd3;
                pm10 <= 2'd3;
                pm11 <= 2'd3;
            end else begin
                pm00 <= pm_new00;
                pm01 <= pm_new01;
                pm10 <= pm_new10;
                pm11 <= pm_new11;
            end
        end
    end

    // ------------------------------------------------------------------
    // 3) dec_s0 (ghi ở ST_01B từ dec_even_latched - E_0)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s0 <= 4'b0;
        else if (we_d01_even) dec_s0 <= dec_even_latched;
    end

    // ------------------------------------------------------------------
    // 4) dec_s1 (ghi ở ST_01B từ dec_odd - O_0)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s1 <= 4'b0;
        else if (we_d01_odd)  dec_s1 <= dec_odd;
    end

    // ------------------------------------------------------------------
    // 5) dec_s2 (ghi ở ST_23B từ dec_even_latched - E_1)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s2 <= 4'b0;
        else if (we_d23_even) dec_s2 <= dec_even_latched;
    end

    // ------------------------------------------------------------------
    // 6) dec_s3 (ghi ở ST_23B từ dec_odd - O_1)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s3 <= 4'b0;
        else if (we_d23_odd)  dec_s3 <= dec_odd;
    end

    // ------------------------------------------------------------------
    // 7) dec_s4 (ghi ở ST_45B từ dec_even_latched - E_2)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s4 <= 4'b0;
        else if (we_d45_even) dec_s4 <= dec_even_latched;
    end

    // ------------------------------------------------------------------
    // 8) dec_s5 (ghi ở ST_45B từ dec_odd - O_2)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s5 <= 4'b0;
        else if (we_d45_odd)  dec_s5 <= dec_odd;
    end

    // ------------------------------------------------------------------
    // 9) dec_s6 / dec_s7 (cùng ghi ở ST_67B)
    //    dec_s6 <- dec_even_latched[1:0] (E_3, chỉ 2 bit thấp dùng cho traceback)
    //    dec_s7 <- dec_odd[0]            (O_3[0])
    //    Mapping này match baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s6 <= 2'b0;
        else if (we_d67_even) dec_s6 <= dec_even_latched[1:0];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s7 <= 1'b0;
        else if (we_d67_odd)  dec_s7 <= dec_odd[0];
    end

    // ------------------------------------------------------------------
    // 7a) o_data
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data <= 8'b0;
        end else if (we_out) begin
            o_data <= tb_out;
        end
    end

    // ------------------------------------------------------------------
    // 7b) o_done
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_done <= 1'b0;
        end else begin
            o_done <= output_cycle;
        end
    end

endmodule
