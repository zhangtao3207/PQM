`timescale 1ns/1ps

// Elaboration-trimmed coefficient lookup for one RFG lane.
// Constant phase options are evaluated through the existing 512-step table.
module e01_rfg_bin_twiddle_q24 #(
    parameter integer C_N = 64,
    parameter integer C_K = 24,
    parameter integer C_D = 1,
    parameter integer C_LANE = 0
) (
    input  wire [8:0]               i_batch_index,   // Zero-based D-bin batch index
    output wire signed [25:0]       o_cosine,        // cos(2*pi*bin/64) in signed Q2.24
    output wire signed [25:0]       o_negative_sine  // -sin(2*pi*bin/64) in signed Q2.24
);
    localparam integer C_BATCHES = (C_K+C_D-1)/C_D;
    localparam integer C_N_SHIFT = 9-$clog2(C_N);

    wire signed [25:0] cosine_options [0:C_BATCHES-1];
    wire signed [25:0] negative_sine_options [0:C_BATCHES-1];
    genvar batch;
    generate
        for (batch = 0; batch < C_BATCHES; batch = batch+1) begin : g_option
            localparam integer C_BIN = batch*C_D+C_LANE+1;
            localparam [8:0] C_PHASE_INDEX = C_BIN << C_N_SHIFT;
            if (C_BIN <= C_K) begin : g_active
                e01_rfg_twiddle_q24 u_constant_twiddle (
                    .i_phase_index(C_PHASE_INDEX),
                    .o_cosine(cosine_options[batch]),
                    .o_sine(negative_sine_options[batch])
                );
            end else begin : g_inactive
                assign cosine_options[batch] = 26'sd0;
                assign negative_sine_options[batch] = 26'sd0;
            end
        end
    endgenerate

    assign o_cosine = cosine_options[i_batch_index];
    assign o_negative_sine = negative_sine_options[i_batch_index];

`ifndef SYNTHESIS
    initial begin
        if (!(C_N == 64 || C_N == 128 || C_N == 256 || C_N == 512))
            $error("C_N must be 64, 128, 256, or 512");
    end
`endif
endmodule
