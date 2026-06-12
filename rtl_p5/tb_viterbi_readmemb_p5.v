`timescale 1ns/1ps

// Testbench for viterbi_decoder_p5.
//
// Identical to tb/tb_viterbi_readmemb.v except:
//   - DUT is `viterbi_decoder_p5` (10-state FSM, 7-cycle latency).
//   - 8 cycles of idle gap are inserted between consecutive `en` pulses
//     to give the longer pipeline time to drain.
//
// Reads the same vector files:
//   ../Viterbi_input_error.txt
//   ../Viterbi_output_error.txt
// (Testbench dùng đường dẫn tương đối ../ nên phải chạy từ rtl_p5/.)
module tb_viterbi_readmemb_p5;

    reg         clk;
    reg         rst_n;
    reg         en;
    reg  [15:0] i_data;
    wire [7:0]  o_data;
    wire        o_done;

    viterbi_decoder_p5 dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (en),
        .i_data (i_data),
        .o_data (o_data),
        .o_done (o_done)
    );

    // 200 MHz clock
    always #2.5 clk = ~clk;

    reg [15:0] coded_mem [0:2047];
    reg [7:0]  exp_mem   [0:2047];

    integer i;
    integer pass;
    integer fail;
    integer idle_cnt;

    initial begin
        clk    = 1'b0;
        rst_n  = 1'b0;
        en     = 1'b0;
        i_data = 16'b0;
        pass   = 0;
        fail   = 0;

        $readmemb("../Viterbi_input_error.txt", coded_mem);
        $readmemb("../Viterbi_output_error.txt",  exp_mem);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        for (i = 0; i < 1024; i = i + 1) begin
            @(negedge clk);
            i_data = coded_mem[i];
            en     = 1'b1;

            @(negedge clk);
            en     = 1'b0;
            i_data = 16'b0;

            wait (o_done === 1'b1);
            #1;

            if (o_data === exp_mem[i]) begin
                pass = pass + 1;
            end else begin
                fail = fail + 1;
                if (fail < 20) begin
                    $display("FAIL idx=%0d coded=%b exp=%b got=%b",
                             i, coded_mem[i], exp_mem[i], o_data);
                end
            end

            // P5 latency = 7 cycles; allow 8 idle cycles between frames
            // so the FSM returns to ST_IDLE before the next en.
            for (idle_cnt = 0; idle_cnt < 8; idle_cnt = idle_cnt + 1) begin
                @(posedge clk);
            end
        end

        $display("RESULT pass=%0d fail=%0d total=%0d", pass, fail, pass + fail);
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
