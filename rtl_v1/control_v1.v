`timescale 1ns/1ps

// Control FSM for rtl_v1 — 13 states (10 ACS phases + 3 traceback pipeline).
//
// Pipeline schedule for one frame (latency en -> o_done = 9 cycles):
//   ST_IDLE : wait for `en` (load_frame = en & (state == ST_IDLE))
//   ST_01A  : phase A — ACS_even (acs_csms) computes pm_mid
//   ST_01B  : phase B — ACS_odd computes pm_new from pipereg_pm_mid
//   ST_23A / ST_23B : ditto for next pair
//   ST_45A / ST_45B : ditto
//   ST_67A / ST_67B : ditto for terminator pair
//   ST_TB1  : traceback stage 1 — tb_state_ff1 <= {1'b0, dec_s7}
//   ST_TB2  : traceback stage 2 — tb_state_ff2 <= {tb_state_ff1[0], dec_s6[tb_state_ff1]}
//   ST_TB3  : traceback stage 3 — tb_out <= f(tb_state_ff2, dec_s5..dec_s1)
//   ST_OUT  : o_data <= tb_out, o_done pulse
//   -> ST_IDLE
//
// `active`     = 1 in any ST_*A or ST_*B (drives pipereg, pm_reg, rx_reg shift).
// `active_a`   = 1 only in ST_*A. Drives BMU operand-iso và dec_even_latched.
// `tb_enable`  = 1 in ST_TB1, ST_TB2, ST_TB3. Drives traceback_pipelined FF.
// `output_cycle` = 1 in ST_OUT (drives o_data / o_done).
module control_v1 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [3:0] state,
    output wire       load_frame,
    output wire       active,
    output wire       active_a,
    output wire       tb_enable,
    output wire       output_cycle
);

    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_01A  = 4'd1, ST_01B = 4'd2;
    localparam [3:0] ST_23A  = 4'd3, ST_23B = 4'd4;
    localparam [3:0] ST_45A  = 4'd5, ST_45B = 4'd6;
    localparam [3:0] ST_67A  = 4'd7, ST_67B = 4'd8;
    localparam [3:0] ST_TB1  = 4'd9, ST_TB2 = 4'dA, ST_TB3 = 4'dB;
    localparam [3:0] ST_OUT  = 4'dC;

    assign load_frame   = (state == ST_IDLE) & en;
    assign active       = (state == ST_01A) | (state == ST_01B) |
                          (state == ST_23A) | (state == ST_23B) |
                          (state == ST_45A) | (state == ST_45B) |
                          (state == ST_67A) | (state == ST_67B);
    assign active_a     = (state == ST_01A) | (state == ST_23A) |
                          (state == ST_45A) | (state == ST_67A);
    assign tb_enable    = (state == ST_TB1) | (state == ST_TB2) |
                          (state == ST_TB3);
    assign output_cycle = (state == ST_OUT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: state <= en ? ST_01A : ST_IDLE;
                ST_01A:  state <= ST_01B;
                ST_01B:  state <= ST_23A;
                ST_23A:  state <= ST_23B;
                ST_23B:  state <= ST_45A;
                ST_45A:  state <= ST_45B;
                ST_45B:  state <= ST_67A;
                ST_67A:  state <= ST_67B;
                ST_67B:  state <= ST_TB1;
                ST_TB1:  state <= ST_TB2;
                ST_TB2:  state <= ST_TB3;
                ST_TB3:  state <= ST_OUT;
                ST_OUT:  state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
