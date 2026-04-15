`timescale 1ns / 1ps

/*
 * Module: ad7606_adc_model
 * Purpose:
 *   Minimal AD7606 parallel-interface behavior model for the top-level testbench.
 *   It reproduces the basic BUSY, FRSTDATA, RD and 8-channel readback behavior
 *   expected by ad7606_parallel_ctrl.
 *
 * Inputs:
 *   clk: Behavior-model clock.
 *   rst_n: Active-low reset.
 *   ad_reset: ADC RESET from the DUT, active high.
 *   ad_convst: ADC CONVST from the DUT.
 *   ad_cs_n: ADC CS# from the DUT, active low.
 *   ad_rd_n: ADC RD# from the DUT, active low.
 *
 * Outputs:
 *   ad_busy: ADC BUSY response.
 *   ad_frstdata: ADC FRSTDATA response.
 *   ad_data: ADC DB[15:0] response.
 */
module ad7606_adc_model(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ad_reset,
    input  wire        ad_convst,
    input  wire        ad_cs_n,
    input  wire        ad_rd_n,
    output reg         ad_busy,
    output wire        ad_frstdata,
    output reg [15:0]  ad_data
);

localparam integer BUSY_ASSERT_DELAY_CYCLES = 4;
localparam integer BUSY_HIGH_CYCLES         = 16;
localparam [15:0]  ZERO_CODE                = 16'd32768;
localparam [21:0]  U_PHASE_STEP             = 22'd1250;
localparam [21:0]  I_PHASE_OFFSET           = 22'd349525;

reg         ad_convst_d;
reg         ad_rd_n_d;
reg         ad_cs_n_d;
reg         conversion_pending;
reg [15:0]  busy_delay_cnt;
reg [15:0]  busy_high_cnt;
reg [2:0]   read_index;
reg [21:0]  u_phase_acc;

reg [15:0]  frame_ch1;
reg [15:0]  frame_ch2;
reg [15:0]  frame_ch3;
reg [15:0]  frame_ch4;
reg [15:0]  frame_ch5;
reg [15:0]  frame_ch6;
reg [15:0]  frame_ch7;
reg [15:0]  frame_ch8;

// Generate deterministic U/I samples from a 64-point sine lookup table.
function [15:0] sine_sample_rom;
    input [5:0] sample_idx;
    begin
        case (sample_idx)
            6'd0:  sine_sample_rom = 16'd32768;
            6'd1:  sine_sample_rom = 16'd33944;
            6'd2:  sine_sample_rom = 16'd35109;
            6'd3:  sine_sample_rom = 16'd36251;
            6'd4:  sine_sample_rom = 16'd37360;
            6'd5:  sine_sample_rom = 16'd38425;
            6'd6:  sine_sample_rom = 16'd39435;
            6'd7:  sine_sample_rom = 16'd40381;
            6'd8:  sine_sample_rom = 16'd41253;
            6'd9:  sine_sample_rom = 16'd42044;
            6'd10: sine_sample_rom = 16'd42746;
            6'd11: sine_sample_rom = 16'd43351;
            6'd12: sine_sample_rom = 16'd43855;
            6'd13: sine_sample_rom = 16'd44251;
            6'd14: sine_sample_rom = 16'd44537;
            6'd15: sine_sample_rom = 16'd44710;
            6'd16: sine_sample_rom = 16'd44768;
            6'd17: sine_sample_rom = 16'd44710;
            6'd18: sine_sample_rom = 16'd44537;
            6'd19: sine_sample_rom = 16'd44251;
            6'd20: sine_sample_rom = 16'd43855;
            6'd21: sine_sample_rom = 16'd43351;
            6'd22: sine_sample_rom = 16'd42746;
            6'd23: sine_sample_rom = 16'd42044;
            6'd24: sine_sample_rom = 16'd41253;
            6'd25: sine_sample_rom = 16'd40381;
            6'd26: sine_sample_rom = 16'd39435;
            6'd27: sine_sample_rom = 16'd38425;
            6'd28: sine_sample_rom = 16'd37360;
            6'd29: sine_sample_rom = 16'd36251;
            6'd30: sine_sample_rom = 16'd35109;
            6'd31: sine_sample_rom = 16'd33944;
            6'd32: sine_sample_rom = 16'd32768;
            6'd33: sine_sample_rom = 16'd31592;
            6'd34: sine_sample_rom = 16'd30427;
            6'd35: sine_sample_rom = 16'd29285;
            6'd36: sine_sample_rom = 16'd28176;
            6'd37: sine_sample_rom = 16'd27111;
            6'd38: sine_sample_rom = 16'd26101;
            6'd39: sine_sample_rom = 16'd25155;
            6'd40: sine_sample_rom = 16'd24283;
            6'd41: sine_sample_rom = 16'd23492;
            6'd42: sine_sample_rom = 16'd22790;
            6'd43: sine_sample_rom = 16'd22185;
            6'd44: sine_sample_rom = 16'd21681;
            6'd45: sine_sample_rom = 16'd21285;
            6'd46: sine_sample_rom = 16'd20999;
            6'd47: sine_sample_rom = 16'd20826;
            6'd48: sine_sample_rom = 16'd20768;
            6'd49: sine_sample_rom = 16'd20826;
            6'd50: sine_sample_rom = 16'd20999;
            6'd51: sine_sample_rom = 16'd21285;
            6'd52: sine_sample_rom = 16'd21681;
            6'd53: sine_sample_rom = 16'd22185;
            6'd54: sine_sample_rom = 16'd22790;
            6'd55: sine_sample_rom = 16'd23492;
            6'd56: sine_sample_rom = 16'd24283;
            6'd57: sine_sample_rom = 16'd25155;
            6'd58: sine_sample_rom = 16'd26101;
            6'd59: sine_sample_rom = 16'd27111;
            6'd60: sine_sample_rom = 16'd28176;
            6'd61: sine_sample_rom = 16'd29285;
            6'd62: sine_sample_rom = 16'd30427;
            6'd63: sine_sample_rom = 16'd31592;
            default: sine_sample_rom = ZERO_CODE;
        endcase
    end
endfunction

// Prepare one 8-channel conversion frame after each CONVST event.
task prepare_frame_data;
    reg [21:0] i_phase_acc;
    reg [15:0] u_display_code;
    reg [15:0] i_display_code;
    begin
        i_phase_acc    = u_phase_acc + I_PHASE_OFFSET;
        u_display_code = sine_sample_rom(u_phase_acc[21:16]);
        i_display_code = sine_sample_rom(i_phase_acc[21:16]);

        frame_ch1 = u_display_code ^ 16'h8000;
        frame_ch2 = 16'h0000;
        frame_ch3 = i_display_code ^ 16'h8000;
        frame_ch4 = 16'h0000;
        frame_ch5 = 16'h0000;
        frame_ch6 = 16'h0000;
        frame_ch7 = 16'h0000;
        frame_ch8 = 16'h0000;

        u_phase_acc = u_phase_acc + U_PHASE_STEP;
    end
endtask

// Assert FRSTDATA only during the first read window.
assign ad_frstdata = (!ad_busy && !ad_cs_n && !ad_rd_n && (read_index == 3'd0));

// Return the current channel word according to the read index.
always @(*) begin
    case (read_index)
        3'd0: ad_data = frame_ch1;
        3'd1: ad_data = frame_ch2;
        3'd2: ad_data = frame_ch3;
        3'd3: ad_data = frame_ch4;
        3'd4: ad_data = frame_ch5;
        3'd5: ad_data = frame_ch6;
        3'd6: ad_data = frame_ch7;
        default: ad_data = frame_ch8;
    endcase
end

// Reproduce the basic CONVST -> BUSY -> RD readout behavior expected by the DUT.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ad_convst_d        <= 1'b1;
        ad_rd_n_d          <= 1'b1;
        ad_cs_n_d          <= 1'b1;
        conversion_pending <= 1'b0;
        busy_delay_cnt     <= 16'd0;
        busy_high_cnt      <= 16'd0;
        read_index         <= 3'd0;
        u_phase_acc        <= 22'd0;
        ad_busy            <= 1'b0;
        frame_ch1          <= 16'h0000;
        frame_ch2          <= 16'h0000;
        frame_ch3          <= 16'h0000;
        frame_ch4          <= 16'h0000;
        frame_ch5          <= 16'h0000;
        frame_ch6          <= 16'h0000;
        frame_ch7          <= 16'h0000;
        frame_ch8          <= 16'h0000;
    end else if (ad_reset) begin
        ad_convst_d        <= ad_convst;
        ad_rd_n_d          <= ad_rd_n;
        ad_cs_n_d          <= ad_cs_n;
        conversion_pending <= 1'b0;
        busy_delay_cnt     <= 16'd0;
        busy_high_cnt      <= 16'd0;
        read_index         <= 3'd0;
        u_phase_acc        <= 22'd0;
        ad_busy            <= 1'b0;
        frame_ch1          <= 16'h0000;
        frame_ch2          <= 16'h0000;
        frame_ch3          <= 16'h0000;
        frame_ch4          <= 16'h0000;
        frame_ch5          <= 16'h0000;
        frame_ch6          <= 16'h0000;
        frame_ch7          <= 16'h0000;
        frame_ch8          <= 16'h0000;
    end else begin
        ad_convst_d <= ad_convst;
        ad_rd_n_d   <= ad_rd_n;
        ad_cs_n_d   <= ad_cs_n;

        if (!ad_convst_d && ad_convst && !conversion_pending && !ad_busy) begin
            prepare_frame_data;
            conversion_pending <= 1'b1;
            busy_delay_cnt     <= BUSY_ASSERT_DELAY_CYCLES;
            read_index         <= 3'd0;
        end

        if (conversion_pending) begin
            if (busy_delay_cnt == 16'd0) begin
                conversion_pending <= 1'b0;
                ad_busy            <= 1'b1;
                busy_high_cnt      <= BUSY_HIGH_CYCLES;
            end else begin
                busy_delay_cnt <= busy_delay_cnt - 16'd1;
            end
        end else if (ad_busy) begin
            if (busy_high_cnt == 16'd0)
                ad_busy <= 1'b0;
            else
                busy_high_cnt <= busy_high_cnt - 16'd1;
        end

        if (ad_cs_n) begin
            read_index <= 3'd0;
        end else if (!ad_rd_n_d && ad_rd_n) begin
            if (read_index != 3'd7)
                read_index <= read_index + 3'd1;
        end
    end
end

endmodule
