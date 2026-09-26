`timescale 1ns/1ps

// Shared Q2.24 twiddle policy for the E01 fairness experiment.
// The coefficient source and four exact trivial phases are common to FFT
// and RFG; RFG L-specific folding constants remain native to each L.
module e01_twiddle_policy_q24 #(
    parameter C_TWIDDLE_POLICY = "shared_q24_lut"
) (
    input  wire [8:0]               i_phase_index,
    output wire signed [25:0]       o_cosine,
    output wire signed [25:0]       o_negative_sine,
    output wire                     o_trivial
);
    generate
        if (C_TWIDDLE_POLICY == "shared_q24_lut") begin : g_shared_q24_lut
            e01_fft_twiddle_q24 u_shared_table (
                .i_phase_index(i_phase_index),
                .o_cosine(o_cosine),
                .o_sine(o_negative_sine)
            );
        end else begin : g_invalid_policy
            initial $error("C_TWIDDLE_POLICY must be shared_q24_lut");
            assign o_cosine = 26'sd0;
            assign o_negative_sine = 26'sd0;
        end
    endgenerate

    assign o_trivial = (i_phase_index == 9'd0) ||
                       (i_phase_index == 9'd128) ||
                       (i_phase_index == 9'd256) ||
                       (i_phase_index == 9'd384);
endmodule
