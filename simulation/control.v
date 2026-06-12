`timescale 1ns/1ps

// Control FSM for one 16-bit encoded frame.
// Latency: load cycle + 4 ACS cycles + 1 output cycle.
module control (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [2:0] state,
    output wire       load_frame,
    output wire       active,
    output wire       output_cycle
);

    localparam ST_IDLE = 3'b000;
    localparam ST_01   = 3'b001;
    localparam ST_23   = 3'b010;
    localparam ST_45   = 3'b011;
    localparam ST_67   = 3'b100;
    localparam ST_OUT  = 3'b101;

    assign load_frame   = (state == ST_IDLE) & en;
    assign active       = (state == ST_01) | (state == ST_23) |
                          (state == ST_45) | (state == ST_67);
    assign output_cycle = (state == ST_OUT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: state <= en ? ST_01 : ST_IDLE;
                ST_01:   state <= ST_23;
                ST_23:   state <= ST_45;
                ST_45:   state <= ST_67;
                ST_67:   state <= ST_OUT;
                ST_OUT:  state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule


