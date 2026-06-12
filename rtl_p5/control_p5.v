`timescale 1ns/1ps

// Control FSM for P5 — 10 states (6 -> 10).
//
// Pipeline schedule for one frame (latency = 7 cycles):
//   ST_IDLE : wait for `en`
//   ST_01A  : phase A — ACS_even computes pm_mid from (pm, bm_a); pipereg latch
//   ST_01B  : phase B — pipereg latched, ACS_odd computes pm_new from (pm_mid, bm_b)
//   ST_23A / ST_23B : ditto, after rx_reg <<= 4
//   ST_45A / ST_45B : ditto
//   ST_67A / ST_67B : ditto
//   ST_OUT  : traceback -> o_data, o_done pulse
//   -> ST_IDLE
//
// `active`     = 1 in any ST_*A or ST_*B (we_pm, we_pipereg, rx_reg shift).
// `active_a`   = 1 only in ST_*A. Drives branch_metric_p5 operand-isolation
//                so the BMU/ACS tree settles to constant when not consuming
//                a new symbol pair.
// `output_cycle` = 1 in ST_OUT (drives o_data / o_done).
module control_p5 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [3:0] state,
    output wire       load_frame,
    output wire       active,
    output wire       active_a,
    output wire       output_cycle
);

    localparam [3:0] ST_IDLE = 4'd0;
    localparam [3:0] ST_01A  = 4'd1;
    localparam [3:0] ST_01B  = 4'd2;
    localparam [3:0] ST_23A  = 4'd3;
    localparam [3:0] ST_23B  = 4'd4;
    localparam [3:0] ST_45A  = 4'd5;
    localparam [3:0] ST_45B  = 4'd6;
    localparam [3:0] ST_67A  = 4'd7;
    localparam [3:0] ST_67B  = 4'd8;
    localparam [3:0] ST_OUT  = 4'd9;

    assign load_frame   = (state == ST_IDLE) & en;
    assign active       = (state == ST_01A) | (state == ST_01B) |
                          (state == ST_23A) | (state == ST_23B) |
                          (state == ST_45A) | (state == ST_45B) |
                          (state == ST_67A) | (state == ST_67B);
    assign active_a     = (state == ST_01A) | (state == ST_23A) |
                          (state == ST_45A) | (state == ST_67A);
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
                ST_67B:  state <= ST_OUT;
                ST_OUT:  state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
