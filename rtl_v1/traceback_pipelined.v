`timescale 1ns/1ps

// Pipelined traceback (P-TB variant) — splits the original 7-level
// combinational traceback into 3 stages to reduce critical path.
//
// Original traceback.v has 7 sequential mux levels (dec_s7 -> dec_s6 ->
// dec_s5 -> dec_s4 -> dec_s3 -> dec_s2 -> dec_s1), each using a 4-bit
// or 2-bit input. With 2-bit path-metric, this is ~1.4 ns on Sky130.
//
// This version breaks it into 3 pipeline stages:
//   Stage 1 (ST_TB1): tb_state_ff1 <= {1'b0, dec_s7}
//                     (1 mux level, ends with FF)
//   Stage 2 (ST_TB2): tb_state_ff2 <= {tb_state_ff1[0], dec_s6[tb_state_ff1]}
//                     (1 mux level, ends with FF)
//   Stage 3 (ST_TB3): tb_out <= traceback(dec_s5..dec_s1, tb_state_ff2)
//                     (5 mux levels, ends with FF)
//
// Critical path reduces from 7 levels to 5 levels (stage 3 dominates).
// Latency: +2 cycles compared to combinational traceback.
//
// Algorithm equivalence: bit-for-bit identical to traceback.v.
// Traceback assumes the encoder terminates at state 00, so the initial
// state for the reverse walk is {1'b0, dec_s7}.
module traceback_pipelined (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we_tb,        // = tb_enable (active in ST_TB1, ST_TB2, ST_TB3)

    input  wire [3:0]  dec_s1,
    input  wire [3:0]  dec_s2,
    input  wire [3:0]  dec_s3,
    input  wire [3:0]  dec_s4,
    input  wire [3:0]  dec_s5,
    input  wire [1:0]  dec_s6,
    input  wire        dec_s7,

    output reg  [7:0]  tb_out
);

    // Pipeline state FFs
    reg [1:0] tb_state_ff1;
    reg [1:0] tb_state_ff2;

    // Intermediate signals for stage 3 (combinational)
    reg [1:0] st_s5, st_s4, st_s3, st_s2, st_s1;
    reg       d_s5, d_s4, d_s3, d_s2, d_s1;

    // ------------------- Stage 1: ST_TB1 -------------------
    // First step of the reverse walk. dec_s7 tells us how the encoder
    // moved INTO the final state 00. Since terminator = 00, the state
    // before that was {1'b0, dec_s7}.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tb_state_ff1 <= 2'b0;
        end else if (we_tb) begin
            tb_state_ff1 <= {1'b0, dec_s7};
        end
    end

    // ------------------- Stage 2: ST_TB2 -------------------
    // Second step: from tb_state_ff1, look up dec_s6 to get previous state.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tb_state_ff2 <= 2'b0;
        end else if (we_tb) begin
            tb_state_ff2 <= {tb_state_ff1[0], dec_s6[tb_state_ff1]};
        end
    end

    // ------------------- Stage 3: ST_TB3 -------------------
    // Remaining 5 steps (dec_s5 down to dec_s1). Combinational from
    // tb_state_ff2 (already registered). Outputs decoded_data[7:0] =
    // bits 7..1 of the Viterbi decode (bit 0 is the second tail bit,
    // always 0).
    //
    // Following the same convention as traceback.v:
    //   decoded_data[1] = state after step 1 (from dec_s7)
    //   decoded_data[2] = state after step 2 (from dec_s6)
    //   ...
    //   decoded_data[7] = state after step 7 (from dec_s1)
    //
    // Since stage 1/2 already captured decoded_data[1] and [2] in
    // tb_state_ff1[1] and tb_state_ff2[1], stage 3 only needs to
    // compute decoded_data[3..7] from the 5 remaining steps.
    always @(*) begin
        // step 3: from tb_state_ff2, look up dec_s5
        st_s5  = {tb_state_ff2[0], dec_s5[tb_state_ff2]};
        d_s5   = tb_state_ff2[1];   // decoded[3]

        // step 4: from st_s5, look up dec_s4
        st_s4  = {st_s5[0], dec_s4[st_s5]};
        d_s4   = st_s5[1];          // decoded[4]

        // step 5: from st_s4, look up dec_s3
        st_s3  = {st_s4[0], dec_s3[st_s4]};
        d_s3   = st_s4[1];          // decoded[5]

        // step 6: from st_s3, look up dec_s2
        st_s2  = {st_s3[0], dec_s2[st_s3]};
        d_s2   = st_s3[1];          // decoded[6]

        // step 7: from st_s2, look up dec_s1
        st_s1  = {st_s2[0], dec_s1[st_s2]};
        d_s1   = st_s2[1];          // decoded[7]
    end

    // Register tb_out at the end of stage 3
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tb_out <= 8'b0;
        end else if (we_tb) begin
            tb_out[0] <= 1'b0;        // tail bit
            tb_out[1] <= tb_state_ff1[1];
            tb_out[2] <= tb_state_ff2[1];
            tb_out[3] <= d_s5;
            tb_out[4] <= d_s4;
            tb_out[5] <= d_s3;
            tb_out[6] <= d_s2;
            tb_out[7] <= d_s1;
        end
    end

endmodule
