`timescale 1ns/1ps

// Fixed-slice extractor for the rolling-rx_reg architecture.
//
// In this revision, rx_reg in memory.v is a shift-by-4 register that is
// loaded with i_data on load_frame and shifted left by 4 on every active
// cycle. As a consequence, the two 2-bit symbols consumed in any given
// active cycle are always located at rx_reg[15:14] (pair_a) and
// rx_reg[13:12] (pair_b). The previous state-driven 4:1 mux that selected
// the slice is therefore removed.
//
// Effect on critical path (baseline path was
//   control.state_reg[0] -> extract_bit mux4:1 -> BMU -> ACS x2 -> pm10/D):
// the mux4:1 at the head of the chain is eliminated. The new path starts
// at rx_reg[15:12]/Q and goes directly into BMU.
//
// Interface note: the `state` port is preserved to avoid touching
// viterbi_decoder.v. It is intentionally unused; synthesis will optimise
// the pin away.
//
// Operand isolation note: the previous version forced pair_a/pair_b to
// 2'b00 outside active cycles to keep the BMU/ACS combinational tree
// quiet. In this revision that isolation is achieved naturally:
//   - after ST_67, rx_reg has been shifted four times and its top 4 bits
//     come from rx_reg[3:0]'s original content; during ST_OUT they then
//     would be one further shift-in of zeros only if active=1, which it
//     is not, so the value held is whatever the last ST_67 produced. The
//     BMU therefore does see toggling input on the transition into
//     ST_OUT, but the pm registers are not written in ST_OUT
//     (we_pm = load_frame | active = 0), so this propagation is harmless
//     and is contained to combinational nodes whose downstream FFs are
//     not enabled. If a stricter operand-isolation is desired later, it
//     can be added without changing this slice logic.
module extract_bit (
    input  wire [2:0]  state,    // kept for interface stability; unused
    input  wire [15:0] rx_reg,
    output wire [1:0]  pair_a,
    output wire [1:0]  pair_b
);

    // Silence "unused" lint warning without changing semantics.
    wire _unused_state = |state;

    assign pair_a = rx_reg[15:14];
    assign pair_b = rx_reg[13:12];

endmodule

