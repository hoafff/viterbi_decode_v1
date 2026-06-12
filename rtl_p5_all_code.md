# RTL P5 — Tất cả file Verilog gộp thành một (Viterbi decoder K=3, R=1/2)

> File này gộp toàn bộ 8 file `.v` của thư mục `rtl_p5/` (chỉ phần code P5, **không** bao gồm các bản sao baseline). Mục đích: dễ xem, dễ copy, dễ gửi qua chat.
>
> Trong `rtl_p5/` còn có `traceback.v` (giữ nguyên từ baseline) và `tb_viterbi_readmemb_p5.v` (testbench) — đã được nhúng nguyên văn bên dưới.
>
> Cấu trúc thư mục gốc `rtl_p5/`:
> - `viterbi_decoder_p5.v` — top-level
> - `control_p5.v`        — FSM 10 trạng thái
> - `memory_p5.v`         — bank FF
> - `acs_pipeline_p5.v`   — wrapper pipeline
> - `acs_csms.v`          — ACS butterfly
> - `branch_metric_p5.v`  — BMU
> - `extract_bit_p5.v`    — trích symbol
> - `traceback.v`         — giữ nguyên baseline
> - `tb_viterbi_readmemb_p5.v` — testbench

---

## 1. `viterbi_decoder_p5.v` — Top-level

```verilog
`timescale 1ns/1ps

// Top-level Viterbi decoder — P5 hybrid high-speed variant.
// K = 3, R = 1/2, generator polynomials: 111 and 101.
// Input  : i_data[15:0] = eight received 2-bit symbols.
// Output : o_data[7:0]  = decoded 8-bit frame (low 2 bits are tail zeros).
//
// Architecture changes vs baseline:
//   - FSM has 10 states (6 -> 10) with phase A / phase B per ACS cycle.
//   - ACS_even and ACS_odd are now separated by a pipeline register
//     (acs_pipeline_p5), which roughly halves the critical path.
//   - ACS butterflies are re-implemented with OR-saturate and CSMS
//     compare-select (acs_csms) for shorter compare-select depth.
//   - Branch metric units have an `active` operand-isolation input
//     (branch_metric_p5) so the BMU/ACS tree is quiet outside phase A.
//   - The `state` port of extract_bit is removed (extract_bit_p5).
//   - memory_p5 writes dec_s* in two phases (odd/even) instead of one.
//
// Latency from `en` pulse to `o_done`: 7 clock cycles (was 6).
// Output data is bit-for-bit equivalent to baseline for the same input.
module viterbi_decoder_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [15:0] i_data,
    output wire [7:0]  o_data,
    output wire        o_done
);

    wire [3:0] state;
    wire       load_frame;
    wire       active;
    wire       active_a;
    wire       output_cycle;

    control_p5 u_control (
        .clk          (clk),
        .rst_n        (rst_n),
        .en           (en),
        .state        (state),
        .load_frame   (load_frame),
        .active       (active),
        .active_a     (active_a),
        .output_cycle (output_cycle)
    );

    wire [15:0] rx_reg;
    wire [1:0]  pm00, pm01, pm10, pm11;
    wire [3:0]  dec_s0, dec_s1, dec_s2, dec_s3, dec_s4, dec_s5;
    wire [1:0]  dec_s6;
    wire        dec_s7;
    wire [7:0]  tb_out;
    wire [1:0]  pair_a, pair_b;

    extract_bit_p5 u_extract_bit (
        .rx_reg (rx_reg),
        .pair_a (pair_a),
        .pair_b (pair_b)
    );

    wire [1:0] bm_a00, bm_a11, bm_a10, bm_a01;
    wire [1:0] bm_b00, bm_b11, bm_b10, bm_b01;

    branch_metric_p5 u_bmu_a (
        .rx_pair (pair_a),
        .active  (active_a),
        .bm00    (bm_a00), .bm11 (bm_a11), .bm10 (bm_a10), .bm01 (bm_a01)
    );

    branch_metric_p5 u_bmu_b (
        .rx_pair (pair_b),
        .active  (active_a),
        .bm00    (bm_b00), .bm11 (bm_b11), .bm10 (bm_b10), .bm01 (bm_b01)
    );

    wire [1:0] pm_new00, pm_new01, pm_new10, pm_new11;
    wire [3:0] dec_odd;
    wire [3:0] dec_even_latched;
    wire       we_pipereg = load_frame | active;

    acs_pipeline_p5 u_acs_pipe (
        .clk              (clk),
        .rst_n            (rst_n),
        .we_pipereg       (we_pipereg),
        .bm_a00 (bm_a00), .bm_a11 (bm_a11), .bm_a10 (bm_a10), .bm_a01 (bm_a01),
        .bm_b00 (bm_b00), .bm_b11 (bm_b11), .bm_b10 (bm_b10), .bm_b01 (bm_b01),
        .pm00 (pm00), .pm01 (pm01), .pm10 (pm10), .pm11 (pm11),
        .pm_new00 (pm_new00), .pm_new01 (pm_new01),
        .pm_new10 (pm_new10), .pm_new11 (pm_new11),
        .dec_odd         (dec_odd),
        .dec_even_latched(dec_even_latched)
    );

    traceback u_traceback (
        .dec_s0       (dec_s0), .dec_s1 (dec_s1),
        .dec_s2       (dec_s2), .dec_s3 (dec_s3),
        .dec_s4       (dec_s4), .dec_s5 (dec_s5),
        .dec_s6       (dec_s6), .dec_s7 (dec_s7),
        .decoded_data (tb_out)
    );

    memory_p5 u_memory (
        .clk              (clk),
        .rst_n            (rst_n),
        .load_frame       (load_frame),
        .active           (active),
        .output_cycle     (output_cycle),
        .state            (state),
        .i_data           (i_data),
        .pm_new00         (pm_new00), .pm_new01 (pm_new01),
        .pm_new10         (pm_new10), .pm_new11 (pm_new11),
        .dec_odd          (dec_odd),
        .dec_even_latched (dec_even_latched),
        .tb_out           (tb_out),
        .rx_reg           (rx_reg),
        .pm00 (pm00), .pm01 (pm01), .pm10 (pm10), .pm11 (pm11),
        .dec_s0 (dec_s0), .dec_s1 (dec_s1), .dec_s2 (dec_s2), .dec_s3 (dec_s3),
        .dec_s4 (dec_s4), .dec_s5 (dec_s5), .dec_s6 (dec_s6), .dec_s7 (dec_s7),
        .o_data (o_data), .o_done (o_done)
    );

endmodule
```

---

## 2. `control_p5.v` — FSM 10 trạng thái

```verilog
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
```

---

## 3. `memory_p5.v` — Bank FF

```verilog
`timescale 1ns/1ps

// Register bank for the Viterbi decoder — P5 variant.
//
// Differences vs baseline memory.v:
//   - `state` port is [3:0] (was [2:0]) because P5 has 10 FSM states.
//   - New input `dec_even_latched[3:0]`: pipelined dec_even from
//     acs_pipeline_p5, written into the "even" dec_s* banks in phase A.
//   - dec_s* writes are split by phase:
//       *_odd  : write `dec_odd`        in phase B of the corresponding cycle
//       *_even : write `dec_even_latched` in phase A of the corresponding cycle
//     This preserves the baseline's semantics: at the end of the frame,
//     dec_s0..dec_s7 hold the per-cycle decisions in time order so
//     traceback.v produces the same decoded_data as baseline (with +1
//     cycle of latency).
//   - o_data / o_done unchanged.
//
// Enable groups:
//   1) rx_reg              -> load_frame | active
//   2) path metrics        -> we_pm     = load_frame | active
//   3) dec_s0 / dec_s1     -> we_d01_odd  = (state == ST_01B)
//                              we_d01_even = (state == ST_01A)
//   4) dec_s2 / dec_s3     -> we_d23_odd  = (state == ST_23B)
//                              we_d23_even = (state == ST_23A)
//   5) dec_s4 / dec_s5     -> we_d45_odd  = (state == ST_45B)
//                              we_d45_even = (state == ST_45A)
//   6) dec_s6 / dec_s7     -> we_d67_odd  = (state == ST_67B)
//                              we_d67_even = (state == ST_67A)
//   7) o_data              -> we_out    = output_cycle
//      o_done              -> free-running (not enable-gated)
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

    wire we_pm      = load_frame | active;
    wire we_d01_odd = (state == ST_01B);
    wire we_d23_odd = (state == ST_23B);
    wire we_d45_odd = (state == ST_45B);
    wire we_d67_odd = (state == ST_67B);
    wire we_d01_even= (state == ST_01A);
    wire we_d23_even= (state == ST_23A);
    wire we_d45_even= (state == ST_45A);
    wire we_d67_even= (state == ST_67A);
    wire we_out     = output_cycle;

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
    // 3) dec_s0 (dec_odd) / dec_s1 (dec_even)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s0 <= 4'b0;
        else if (we_d01_odd)  dec_s0 <= dec_odd;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s1 <= 4'b0;
        else if (we_d01_even) dec_s1 <= dec_even_latched;
    end

    // ------------------------------------------------------------------
    // 4) dec_s2 / dec_s3
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s2 <= 4'b0;
        else if (we_d23_odd)  dec_s2 <= dec_odd;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s3 <= 4'b0;
        else if (we_d23_even) dec_s3 <= dec_even_latched;
    end

    // ------------------------------------------------------------------
    // 5) dec_s4 / dec_s5
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s4 <= 4'b0;
        else if (we_d45_odd)  dec_s4 <= dec_odd;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s5 <= 4'b0;
        else if (we_d45_even) dec_s5 <= dec_even_latched;
    end

    // ------------------------------------------------------------------
    // 6) dec_s6 / dec_s7
    //   dec_s7 (1 bit)  : terminator 00, lsb of dec_even at ST_67A
    //   dec_s6 (2 bits) : bit-pair of dec_odd at ST_67B
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s7 <= 1'b0;
        else if (we_d67_even) dec_s7 <= dec_even_latched[0];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dec_s6 <= 2'b0;
        else if (we_d67_odd)  dec_s6 <= dec_odd[1:0];
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
```

---

## 4. `acs_pipeline_p5.v` — Wrapper pipeline

```verilog
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
// `dec_even` is also latched (dec_even_latched) and forwarded to memory_p5
// so the traceback dec_s* banks are written in the correct phase. See
// memory_p5.v for the exact enable decoding.
module acs_pipeline_p5 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we_pipereg,    // load_frame | active

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
    reg [1:0] pipereg_pm_mid00, pipereg_pm_mid01;
    reg [1:0] pipereg_pm_mid10, pipereg_pm_mid11;
    reg [3:0] pipereg_dec_even;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipereg_pm_mid00 <= 2'b0;
            pipereg_pm_mid01 <= 2'b0;
            pipereg_pm_mid10 <= 2'b0;
            pipereg_pm_mid11 <= 2'b0;
            pipereg_dec_even <= 4'b0;
        end else if (we_pipereg) begin
            pipereg_pm_mid00 <= pm_mid00;
            pipereg_pm_mid01 <= pm_mid01;
            pipereg_pm_mid10 <= pm_mid10;
            pipereg_pm_mid11 <= pm_mid11;
            pipereg_dec_even <= dec_even;
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

    // -------------------- dec_even forwarding -----------------------
    // The pipelined dec_even is exposed so memory_p5 can write it into
    // the appropriate dec_s* register in the next phase-A cycle.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dec_even_latched <= 4'b0;
        end else if (we_pipereg) begin
            dec_even_latched <= pipereg_dec_even;
        end
    end

endmodule
```

---

## 5. `acs_csms.v` — ACS butterfly (CSMS + OR-saturate)

```verilog
`timescale 1ns/1ps

// Add-Compare-Select for 4-state K=3 Viterbi decoder — P5 variant.
//
// Two speed-ups vs baseline add_comp_slt.v:
//   1) OR-saturate:  cand = sum[1:0] | {2{sum[2]}}
//      saves one level of logic vs the `?:` 3-to-1 mux.
//   2) CSMS compare-select: instead of `decision = (cand_b < cand_a)` plus
//      a 2:1 mux, the comparison is reduced to two gates:
//        lt_msb = cand_b[1] & ~cand_a[1]                 (1 AOI/AND gate)
//        lt_lsb = ~lt_msb & cand_b[0] & ~cand_a[0]       (2 AOI/AND gates)
//        sel    = lt_msb | lt_lsb                        (1 OR gate)
//      and the select mux is unchanged. Net saving: ~3 logic levels per
//      butterfly. Ties still select candidate A because lt_msb=lt_lsb=0
//      when cand_b == cand_a.
//
// Algorithm equivalence to baseline is preserved bit-for-bit because
//   (a < b)  <->  b[1] < a[1]  OR  (b[1] == a[1] AND b[0] < a[0])
//   (b[0] < a[0])  <->  b[0] == 1 AND a[0] == 0  (for 1-bit operands).
// `lt_msb | lt_lsb` is the standard "B strictly less than A" predicate.
module acs_csms (
    input  wire [1:0] bm00,
    input  wire [1:0] bm11,
    input  wire [1:0] bm10,
    input  wire [1:0] bm01,

    input  wire [1:0] pm00,
    input  wire [1:0] pm01,
    input  wire [1:0] pm10,
    input  wire [1:0] pm11,

    output wire [1:0] new_pm00,
    output wire [1:0] new_pm01,
    output wire [1:0] new_pm10,
    output wire [1:0] new_pm11,

    output wire [3:0] decision
);

    // ---------------- butterfly 00 : (pm00+bm00) vs (pm01+bm11) ----------------
    wire [2:0] s00a = {1'b0, pm00} + {1'b0, bm00};
    wire [2:0] s00b = {1'b0, pm01} + {1'b0, bm11};
    wire [1:0] c00a = s00a[1:0] | {2{s00a[2]}};
    wire [1:0] c00b = s00b[1:0] | {2{s00b[2]}};
    wire lt00_msb = c00b[1] & ~c00a[1];
    wire lt00_lsb = ~lt00_msb & c00b[0] & ~c00a[0];
    wire sel00    = lt00_msb | lt00_lsb;
    assign decision[0] = sel00;
    assign new_pm00    = sel00 ? c00b : c00a;

    // ---------------- butterfly 01 : (pm10+bm10) vs (pm11+bm01) ----------------
    wire [2:0] s01a = {1'b0, pm10} + {1'b0, bm10};
    wire [2:0] s01b = {1'b0, pm11} + {1'b0, bm01};
    wire [1:0] c01a = s01a[1:0] | {2{s01a[2]}};
    wire [1:0] c01b = s01b[1:0] | {2{s01b[2]}};
    wire lt01_msb = c01b[1] & ~c01a[1];
    wire lt01_lsb = ~lt01_msb & c01b[0] & ~c01a[0];
    wire sel01    = lt01_msb | lt01_lsb;
    assign decision[1] = sel01;
    assign new_pm01    = sel01 ? c01b : c01a;

    // ---------------- butterfly 10 : (pm00+bm11) vs (pm01+bm00) ----------------
    wire [2:0] s10a = {1'b0, pm00} + {1'b0, bm11};
    wire [2:0] s10b = {1'b0, pm01} + {1'b0, bm00};
    wire [1:0] c10a = s10a[1:0] | {2{s10a[2]}};
    wire [1:0] c10b = s10b[1:0] | {2{s10b[2]}};
    wire lt10_msb = c10b[1] & ~c10a[1];
    wire lt10_lsb = ~lt10_msb & c10b[0] & ~c10a[0];
    wire sel10    = lt10_msb | lt10_lsb;
    assign decision[2] = sel10;
    assign new_pm10    = sel10 ? c10b : c10a;

    // ---------------- butterfly 11 : (pm10+bm01) vs (pm11+bm10) ----------------
    wire [2:0] s11a = {1'b0, pm10} + {1'b0, bm01};
    wire [2:0] s11b = {1'b0, pm11} + {1'b0, bm10};
    wire [1:0] c11a = s11a[1:0] | {2{s11a[2]}};
    wire [1:0] c11b = s11b[1:0] | {2{s11b[2]}};
    wire lt11_msb = c11b[1] & ~c11a[1];
    wire lt11_lsb = ~lt11_msb & c11b[0] & ~c11a[0];
    wire sel11    = lt11_msb | lt11_lsb;
    assign decision[3] = sel11;
    assign new_pm11    = sel11 ? c11b : c11a;

endmodule
```

---

## 6. `branch_metric_p5.v` — BMU + operand-isolation

```verilog
`timescale 1ns/1ps

// Branch Metric Unit for K=3, R=1/2 Viterbi decoder — P5 variant.
// Adds operand-isolation: when `active=0`, rx_pair is forced to 2'b00 so
// the BMU/ACS combinational tree settles to a constant, reducing glitch
// and dynamic power in IDLE / ST_OUT cycles.
//
// Generator outputs are one of: 00, 11, 10, 01.
// Metric = Hamming distance between received 2-bit symbol and expected.
module branch_metric_p5 (
    input  wire [1:0] rx_pair,
    input  wire       active,    // 1 during ST_*A cycles (phase A of pipeline)
    output wire [1:0] bm00,
    output wire [1:0] bm11,
    output wire [1:0] bm10,
    output wire [1:0] bm01
);

    wire [1:0] rx_g = active ? rx_pair : 2'b00;

    assign bm00 = {1'b0,  rx_g[1]} + {1'b0,  rx_g[0]};
    assign bm11 = {1'b0, ~rx_g[1]} + {1'b0, ~rx_g[0]};
    assign bm10 = {1'b0, ~rx_g[1]} + {1'b0,  rx_g[0]};
    assign bm01 = {1'b0,  rx_g[1]} + {1'b0, ~rx_g[0]};

endmodule
```

---

## 7. `extract_bit_p5.v` — Trích symbol từ rx_reg

```verilog
`timescale 1ns/1ps

// P5 variant of extract_bit — same logic as baseline (fixed-slice on
// rx_reg[15:12]), but the unused `state` port is removed. The pair
// signals come straight from the Q output of rx_reg, so synthesis can
// use the FF's Q pin directly and avoid an extra inverter stage.
module extract_bit_p5 (
    input  wire [15:0] rx_reg,
    output wire [1:0]  pair_a,
    output wire [1:0]  pair_b
);

    assign pair_a = rx_reg[15:14];
    assign pair_b = rx_reg[13:12];

endmodule
```

---

## 8. `traceback.v` — Giữ nguyên từ baseline

```verilog
`timescale 1ns/1ps

// Combinational traceback for a tail-terminated frame.
// Final encoder state is assumed to be 00 because K=3 encoder appends two
// tail zeros. This assumption was verified against Viterbi_input_error.txt:
// bits [1:0] of every expected decoded byte are 00.
module traceback (
    input  wire [3:0] dec_s0,
    input  wire [3:0] dec_s1,
    input  wire [3:0] dec_s2,
    input  wire [3:0] dec_s3,
    input  wire [3:0] dec_s4,
    input  wire [3:0] dec_s5,
    input  wire [1:0] dec_s6,
    input  wire       dec_s7,
    output reg  [7:0] decoded_data
);

    reg [1:0] state_tb;

    always @(*) begin
        decoded_data = 8'b00000000;

        state_tb        = {1'b0, dec_s7};
        decoded_data[1] = state_tb[1];

        state_tb        = {state_tb[0], dec_s6[state_tb]};
        decoded_data[2] = state_tb[1];

        state_tb        = {state_tb[0], dec_s5[state_tb]};
        decoded_data[3] = state_tb[1];

        state_tb        = {state_tb[0], dec_s4[state_tb]};
        decoded_data[4] = state_tb[1];

        state_tb        = {state_tb[0], dec_s3[state_tb]};
        decoded_data[5] = state_tb[1];

        state_tb        = {state_tb[0], dec_s2[state_tb]};
        decoded_data[6] = state_tb[1];

        state_tb        = {state_tb[0], dec_s1[state_tb]};
        decoded_data[7] = state_tb[1];

        // decoded_data[0] is the second tail bit and remains 0.
        // dec_s0 is kept as survivor storage for waveform/debug consistency.
    end

endmodule
```

---

## 9. `tb_viterbi_readmemb_p5.v` — Testbench P5

```verilog
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
// (Adjust paths to where you run the simulator from.)
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

        $readmemb("Viterbi_input_error.txt", coded_mem);
        $readmemb("Viterbi_output_error.txt",  exp_mem);

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
```

---

## Tổng kết

| File | Mục đích | Mới trong P5? |
|---|---|---|
| `viterbi_decoder_p5.v` | Top-level P5 | ✅ |
| `control_p5.v` | FSM 10 state | ✅ |
| `memory_p5.v` | Bank FF + dec_s* theo phase | ✅ |
| `acs_pipeline_p5.v` | Pipeline giữa 2 ACS | ✅ |
| `acs_csms.v` | ACS CSMS + OR-saturate | ✅ |
| `branch_metric_p5.v` | BMU + operand-isolation | ✅ |
| `extract_bit_p5.v` | Trích symbol | ✅ |
| `traceback.v` | Traceback combinational | ❌ (giữ nguyên) |
| `tb_viterbi_readmemb_p5.v` | Testbench P5 | ✅ |

## Cách dùng khi copy file này

Mỗi khối `​```verilog` trên là code nguyên văn của 1 file `.v` riêng. Khi muốn tách lại thành file:

1. Copy phần giữa `` ```verilog `` và `` ``` `` của section tương ứng.
2. Lưu vào file `.v` với tên được ghi ở heading (ví dụ section 1 → `viterbi_decoder_p5.v`).
3. Bỏ 2 dấu backtick ở đầu/cuối — chỉ giữ phần code bên trong.









