/*
 * Module: wave_frame_capture
 * Function:
 *   Convert the raw ADC stream into a trigger-aligned waveform frame and
 *   stream the captured frame into the external dual-port RAM. The module
 *   also derives a slow U_rms readout from the same raw samples.
 *
 *   Important:
 *   The old startup-only zero calibration is not suitable for waveform
 *   triggering, because it can lock onto an arbitrary phase point during
 *   power-up. This module therefore tracks the waveform center with a slow
 *   DC estimator for trigger alignment.
 *
 *   For vertical rendering, keep the display referenced to the physical
 *   zero-code instead of the tracked waveform center. That preserves the
 *   absolute offset/amplitude on screen instead of showing only the AC
 *   component around the middle line.
 */
module wave_frame_capture(
    input              wave_clk,
    input              sys_rst_n,
    input      [7:0]   wave_sample_code,
    input      [7:0]   wave_zero_code,
    input              wave_zero_valid,
    output reg  [7:0]  u_rms_tens,
    output reg  [7:0]  u_rms_units,
    output reg  [7:0]  u_rms_decile,
    output reg  [7:0]  u_rms_percentiles,
    output reg         u_rms_digits_valid,
    output reg         wave_frame_valid,
    output reg         wave_display_bank,
    output reg         wave_ram_we,
    output reg [9:0]   wave_ram_waddr,
    output reg [7:0]   wave_ram_wdata
);

localparam integer WAVE_POINT_COUNT  = 384;
localparam integer WAVE_FRAME_TICKS  = 1_000_000;
localparam [7:0]   WAVE_TRIGGER_HYST = 8'd2;
localparam integer GRAPH_H           = 240;
localparam integer GRAPH_HALF_H      = 120;
localparam integer SAMPLE_WIDTH      = 8;
localparam integer CENTER_IIR_SHIFT  = 22;
localparam integer CENTER_ACC_W      = SAMPLE_WIDTH + CENTER_IIR_SHIFT + 2;
localparam [SAMPLE_WIDTH-1:0] CENTER_DEFAULT = 8'd127;

reg  [7:0]  wave_y_hist [0:WAVE_POINT_COUNT-1];
reg  [8:0]  wave_wr_ptr;
reg  [20:0] wave_resample_acc;
reg  [CENTER_ACC_W-1:0] wave_center_acc;
reg         wave_hist_full;
reg         wave_div_start;
reg  [15:0] wave_dividend;
reg  [15:0] wave_divisor;
reg         wave_sample_positive;
reg         wave_trigger_armed;
reg  [7:0]  wave_sample_code_pending;
reg  [7:0]  wave_trigger_code_d0;
reg  [7:0]  wave_trigger_code_d1;
reg  [7:0]  wave_trigger_code_d2;
reg  [7:0]  wave_trigger_code_pending;
reg         wave_resample_pending;
reg         copy_active;
reg  [8:0]  copy_idx;
reg         copy_bank;
reg  [8:0]  copy_wr_ptr_snapshot;
reg  [7:0]  copy_last_y;
reg         copy_commit_pending;
reg         copy_commit_bank;

wire [7:0]  wave_center_code;
wire [7:0]  wave_display_zero_code;
wire [7:0]  wave_trigger_low;
wire [7:0]  wave_trigger_high;
wire [20:0] wave_resample_sum;
wire        wave_div_busy;
wire        wave_div_done;
wire        wave_div_zero;
wire [15:0] wave_div_quotient;
wire [7:0]  u_rms_tens_int;
wire [7:0]  u_rms_units_int;
wire [7:0]  u_rms_decile_int;
wire [7:0]  u_rms_percentiles_int;
wire        u_rms_digits_valid_int;
wire [9:0]  wave_trigger_sum;

integer wave_init_idx;
integer wave_amp_px;
integer wave_y_next;
integer copy_src_idx;
reg [7:0] wave_y_clamped;

assign wave_center_code  = wave_center_acc[CENTER_IIR_SHIFT + SAMPLE_WIDTH - 1:CENTER_IIR_SHIFT];
assign wave_display_zero_code = wave_zero_valid ? wave_zero_code : CENTER_DEFAULT;
assign wave_trigger_low  = (wave_center_code > WAVE_TRIGGER_HYST) ? (wave_center_code - WAVE_TRIGGER_HYST) : 8'd0;
assign wave_trigger_high = (wave_center_code < (8'd255 - WAVE_TRIGGER_HYST)) ? (wave_center_code + WAVE_TRIGGER_HYST) : 8'd255;
assign wave_resample_sum = wave_resample_acc + WAVE_POINT_COUNT;
assign wave_trigger_sum  = {2'b00, wave_sample_code} + {2'b00, wave_trigger_code_d0} +
                           {2'b00, wave_trigger_code_d1} + {2'b00, wave_trigger_code_d2};

signal_rms_calc #(
    .WIDTH         (8),
    .FULL_SCALE_MV (5000),
    .WINDOW_SAMPLES(WAVE_FRAME_TICKS)
) u_signal_rms_calc (
    .clk             (wave_clk),
    .rst_n           (sys_rst_n),
    .sample_code     (wave_sample_code),
    .center_code     (wave_center_code),
    .rms_tens        (u_rms_tens_int),
    .rms_units       (u_rms_units_int),
    .rms_decile      (u_rms_decile_int),
    .rms_percentiles (u_rms_percentiles_int),
    .rms_digits_valid(u_rms_digits_valid_int)
);

divider_unsigned #(
    .WIDTH(16)
) u_wave_amp_divider (
    .clk           (wave_clk),
    .rst_n         (sys_rst_n),
    .start         (wave_div_start),
    .dividend      (wave_dividend),
    .divisor       (wave_divisor),
    .busy          (wave_div_busy),
    .done          (wave_div_done),
    .divide_by_zero(wave_div_zero),
    .quotient      (wave_div_quotient)
);

always @(posedge wave_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        wave_wr_ptr           <= 9'd0;
        wave_resample_acc     <= 21'd0;
        wave_center_acc       <= {CENTER_DEFAULT, {CENTER_IIR_SHIFT{1'b0}}};
        wave_hist_full        <= 1'b0;
        wave_frame_valid      <= 1'b0;
        wave_display_bank     <= 1'b0;
        wave_div_start        <= 1'b0;
        wave_dividend         <= 16'd0;
        wave_divisor          <= 16'd1;
        wave_sample_positive  <= 1'b1;
        wave_trigger_armed    <= 1'b0;
        wave_sample_code_pending <= 8'd0;
        wave_trigger_code_d0  <= 8'd127;
        wave_trigger_code_d1  <= 8'd127;
        wave_trigger_code_d2  <= 8'd127;
        wave_trigger_code_pending <= 8'd127;
        wave_resample_pending <= 1'b0;
        copy_active           <= 1'b0;
        copy_idx              <= 9'd0;
        copy_bank             <= 1'b0;
        copy_wr_ptr_snapshot  <= 9'd0;
        copy_last_y           <= 8'd120;
        copy_commit_pending   <= 1'b0;
        copy_commit_bank      <= 1'b0;
        wave_ram_we           <= 1'b0;
        wave_ram_waddr        <= 10'd0;
        wave_ram_wdata        <= 8'd120;
        u_rms_tens            <= 8'd0;
        u_rms_units           <= 8'd0;
        u_rms_decile          <= 8'd0;
        u_rms_percentiles     <= 8'd0;
        u_rms_digits_valid    <= 1'b0;

        for (wave_init_idx = 0; wave_init_idx < WAVE_POINT_COUNT; wave_init_idx = wave_init_idx + 1)
            wave_y_hist[wave_init_idx] <= 8'd120;
    end else begin
        wave_div_start <= 1'b0;
        wave_ram_we    <= 1'b0;
        wave_center_acc <= wave_center_acc +
                           {{(CENTER_ACC_W - SAMPLE_WIDTH){1'b0}}, wave_sample_code} -
                           {{(CENTER_ACC_W - SAMPLE_WIDTH){1'b0}}, wave_center_code};

        if (u_rms_digits_valid_int) begin
            u_rms_tens         <= u_rms_tens_int;
            u_rms_units        <= u_rms_units_int;
            u_rms_decile       <= u_rms_decile_int;
            u_rms_percentiles  <= u_rms_percentiles_int;
            u_rms_digits_valid <= 1'b1;
        end

        if (copy_commit_pending) begin
            copy_commit_pending <= 1'b0;
            wave_display_bank   <= copy_commit_bank;
            wave_frame_valid    <= 1'b1;
        end

        if (copy_active) begin
            wave_ram_we    <= 1'b1;
            wave_ram_waddr <= {copy_bank, copy_idx};

            if (copy_idx == (WAVE_POINT_COUNT - 1)) begin
                wave_ram_wdata      <= copy_last_y;
                copy_active         <= 1'b0;
                copy_commit_pending <= 1'b1;
                copy_commit_bank    <= copy_bank;
            end else begin
                copy_src_idx = copy_wr_ptr_snapshot + copy_idx + 1;
                if (copy_src_idx >= WAVE_POINT_COUNT)
                    copy_src_idx = copy_src_idx - WAVE_POINT_COUNT;

                wave_ram_wdata <= wave_y_hist[copy_src_idx];
                copy_idx       <= copy_idx + 9'd1;
            end
        end else begin
            if (!wave_resample_pending && !wave_div_busy) begin
                if (wave_resample_sum >= WAVE_FRAME_TICKS) begin
                    wave_resample_acc        <= wave_resample_sum - WAVE_FRAME_TICKS;
                    wave_sample_code_pending <= wave_sample_code;
                    wave_trigger_code_pending <= (wave_trigger_sum + 10'd2) >> 2;
                    wave_resample_pending    <= 1'b1;
                    wave_div_start           <= 1'b1;

                    if (wave_sample_code >= wave_display_zero_code) begin
                        wave_sample_positive <= 1'b1;
                        wave_divisor         <= 16'd128;
                        wave_dividend        <= ({8'd0, (wave_sample_code - wave_display_zero_code)} * (GRAPH_HALF_H - 2)) +
                                                16'd64;
                    end else begin
                        wave_sample_positive <= 1'b0;
                        wave_divisor         <= 16'd128;
                        wave_dividend        <= ({8'd0, (wave_display_zero_code - wave_sample_code)} * (GRAPH_HALF_H - 2)) +
                                                16'd64;
                    end
                end else begin
                    wave_resample_acc <= wave_resample_sum;
                end
            end

            if (wave_div_done && wave_resample_pending) begin
                wave_amp_px = wave_div_zero ? 0 : wave_div_quotient;

                if (wave_sample_positive)
                    wave_y_next = GRAPH_HALF_H - wave_amp_px;
                else
                    wave_y_next = GRAPH_HALF_H + wave_amp_px;

                if (wave_y_next < 1)
                    wave_y_clamped = 8'd1;
                else if (wave_y_next > (GRAPH_H - 2))
                    wave_y_clamped = GRAPH_H - 2;
                else
                    wave_y_clamped = wave_y_next[7:0];

                wave_y_hist[wave_wr_ptr] <= wave_y_clamped;
                wave_trigger_code_d2     <= wave_trigger_code_d1;
                wave_trigger_code_d1     <= wave_trigger_code_d0;
                wave_trigger_code_d0     <= wave_sample_code_pending;

                if (wave_hist_full && wave_trigger_armed &&
                    (wave_trigger_code_pending >= wave_trigger_high)) begin
                    copy_active          <= 1'b1;
                    copy_idx             <= 9'd0;
                    copy_bank            <= ~wave_display_bank;
                    copy_wr_ptr_snapshot <= wave_wr_ptr;
                    copy_last_y          <= wave_y_clamped;
                    wave_trigger_armed   <= 1'b0;
                end else if (wave_trigger_code_pending <= wave_trigger_low) begin
                    // Use a Schmitt-trigger style arming rule so low-frequency
                    // waveforms do not need to jump across the whole hysteresis
                    // band within a single resampled interval.
                    wave_trigger_armed <= 1'b1;
                end

                wave_resample_pending <= 1'b0;

                if (wave_wr_ptr == (WAVE_POINT_COUNT - 1)) begin
                    wave_wr_ptr    <= 9'd0;
                    wave_hist_full <= 1'b1;
                end else begin
                    wave_wr_ptr    <= wave_wr_ptr + 9'd1;
                end
            end
        end
    end
end

endmodule
