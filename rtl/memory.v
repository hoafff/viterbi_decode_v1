`timescale 1ns/1ps

// Register bank for the Viterbi decoder.
//
// Revision note (rolling-rx_reg):
//   rx_reg is now a shift-by-4 register. It is loaded with i_data on
//   load_frame, and shifted left by 4 bits on every active cycle. This
//   pairs with extract_bit which always reads rx_reg[15:14] and
//   rx_reg[13:12]. The symbol order and per-cycle pair values are
//   identical to the baseline state-mux extractor:
//
//     cycle ST_01 : pair_a=i_data[15:14], pair_b=i_data[13:12]
//     cycle ST_23 : pair_a=i_data[11:10], pair_b=i_data[ 9: 8]
//     cycle ST_45 : pair_a=i_data[ 7: 6], pair_b=i_data[ 5: 4]
//     cycle ST_67 : pair_a=i_data[ 3: 2], pair_b=i_data[ 1: 0]
//
//   No other block is modified versus baseline.
//
// Enable groups (unchanged from baseline):
//   1) rx_reg              -> load_frame | active (load vs shift)
//   2) path metrics        -> we_pm     = load_frame | active
//   3) dec_s0 / dec_s1     -> we_d01    = active & state==ST_01
//   4) dec_s2 / dec_s3     -> we_d23    = active & state==ST_23
//   5) dec_s4 / dec_s5     -> we_d45    = active & state==ST_45
//   6) dec_s6 / dec_s7     -> we_d67    = active & state==ST_67
//   7) o_data              -> we_out    = output_cycle
//      o_done              -> free-running (not enable-gated)
module memory (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        load_frame,
    input  wire        active,
    input  wire        output_cycle,
    input  wire [2:0]  state,
    input  wire [15:0] i_data,

    input  wire [1:0]  pm_new00,
    input  wire [1:0]  pm_new01,
    input  wire [1:0]  pm_new10,
    input  wire [1:0]  pm_new11,
    input  wire [3:0]  dec_even,
    input  wire [3:0]  dec_odd,
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

    localparam ST_01 = 3'b001;
    localparam ST_23 = 3'b010;
    localparam ST_45 = 3'b011;
    localparam ST_67 = 3'b100;

    wire we_pm  = load_frame | active;
    wire we_d01 = active & (state == ST_01);
    wire we_d23 = active & (state == ST_23);
    wire we_d45 = active & (state == ST_45);
    wire we_d67 = active & (state == ST_67);
    wire we_out = output_cycle;

    // ------------------------------------------------------------------
    // 1) rx_reg : shift-by-4 register.
    //    - load_frame : rx_reg <= i_data
    //    - active     : rx_reg <= {rx_reg[11:0], 4'b0}
    //    - otherwise  : hold
    //
    //    Functional equivalence to the baseline state-mux extractor is
    //    proven cycle-by-cycle in the patch notes accompanying this
    //    revision. The fixed slice rx_reg[15:14] / rx_reg[13:12] read by
    //    extract_bit yields the same pair_a/pair_b sequence as the
    //    baseline state-driven 4:1 mux.
    //
    //    Power note: rx_reg now toggles up to 4 times per frame (once per
    //    active cycle) instead of once per frame. Switching activity in
    //    these 16 flops therefore increases ~4x. This is the deliberate
    //    trade-off for eliminating the state-driven 4:1 mux from the head
    //    of the BMU/ACS critical path.
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
    // 2) path metrics : unchanged from baseline.
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
    // 3) dec_s0 / dec_s1 : unchanged from baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_s0 <= 4'b0;
            dec_s1 <= 4'b0;
        end else if (we_d01) begin
            dec_s0 <= dec_even;
            dec_s1 <= dec_odd;
        end
    end

    // ------------------------------------------------------------------
    // 4) dec_s2 / dec_s3 : unchanged from baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_s2 <= 4'b0;
            dec_s3 <= 4'b0;
        end else if (we_d23) begin
            dec_s2 <= dec_even;
            dec_s3 <= dec_odd;
        end
    end

    // ------------------------------------------------------------------
    // 5) dec_s4 / dec_s5 : unchanged from baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_s4 <= 4'b0;
            dec_s5 <= 4'b0;
        end else if (we_d45) begin
            dec_s4 <= dec_even;
            dec_s5 <= dec_odd;
        end
    end

    // ------------------------------------------------------------------
    // 6) dec_s6 / dec_s7 : unchanged from baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_s6 <= 2'b0;
            dec_s7 <= 1'b0;
        end else if (we_d67) begin
            dec_s6 <= dec_even[1:0];
            dec_s7 <= dec_odd[0];
        end
    end

    // ------------------------------------------------------------------
    // 7a) o_data : unchanged from baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data <= 8'b0;
        end else if (we_out) begin
            o_data <= tb_out;
        end
    end

    // ------------------------------------------------------------------
    // 7b) o_done : unchanged from baseline.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_done <= 1'b0;
        end else begin
            o_done <= output_cycle;
        end
    end

endmodule

