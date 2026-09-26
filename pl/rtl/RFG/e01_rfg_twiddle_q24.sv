`timescale 1ns/1ps

// Full-circle Q2.24 twiddle wrapper on the shared 512-step FFT table.
// The FFT table stores phases 0..255; the second half follows by pi symmetry.
module e01_rfg_twiddle_q24 (
    input  wire [8:0]               i_phase_index, // Phase index on a 512-step full circle
    output wire signed [25:0]       o_cosine,      // cos(2*pi*index/512) in signed Q2.24
    output wire signed [25:0]       o_sine         // -sin(2*pi*index/512) in signed Q2.24
);
    wire [8:0] half_phase = {1'b0,i_phase_index[7:0]};
    wire signed [25:0] half_cosine;
    wire signed [25:0] half_sine;

    e01_twiddle_policy_q24 u_half_circle (
        .i_phase_index(half_phase),
        .o_cosine(half_cosine),
        .o_negative_sine(half_sine),
        .o_trivial()
    );

    assign o_cosine = i_phase_index[8] ? -half_cosine : half_cosine;
    assign o_sine = i_phase_index[8] ? -half_sine : half_sine;
endmodule
