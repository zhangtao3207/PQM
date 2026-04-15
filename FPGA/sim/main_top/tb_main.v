`timescale 1ns / 1ps

/*
 * Module: tb_main
 * Purpose:
 *   Top-level behavioral testbench for main.v.
 *   It keeps the real LCD/text/measurement chain intact and only models the
 *   external environment that main sees in hardware.
 *
 * Inputs:
 *   None.
 *
 * Outputs:
 *   None.
 */
module tb_main;

localparam integer SYS_CLK_HALF_PERIOD_NS = 10;
localparam integer TARGET_LCD_SWAPS       = 6;
localparam integer MAX_SIM_TIME_NS        = 500_000_000;

localparam [23:0]  PANEL_ID_RGB_7016      = 24'h008000;

// Frequency units digit cell: LINE_X + 13 * CHAR_W, LINE_Y0
localparam integer FREQ_UNITS_X0          = 646;
localparam integer FREQ_UNITS_X1          = 656;
localparam integer FREQ_UNITS_Y0          = 114;
localparam integer FREQ_UNITS_Y1          = 134;
localparam integer FREQ_UNITS_X_CENTER    = 651;
localparam integer FREQ_UNITS_Y_CENTER    = 124;

// Phase Diff units digit cell: LINE_X + 15 * CHAR_W, LINE_Y0 + 3 * LINE_STEP
localparam integer PHASE_UNITS_X0         = 666;
localparam integer PHASE_UNITS_X1         = 676;
localparam integer PHASE_UNITS_Y0         = 198;
localparam integer PHASE_UNITS_Y1         = 218;
localparam integer PHASE_UNITS_X_CENTER   = 671;
localparam integer PHASE_UNITS_Y_CENTER   = 208;

reg         sys_clk;
reg         sys_rst_n;
reg         uart_rxd;

tri1        touch_sda;
wire        touch_scl;
tri1        touch_int;
wire        touch_rst_n;

wire        lcd_de;
wire        lcd_hs;
wire        lcd_vs;
wire        lcd_bl;
wire        lcd_clk;
wire        lcd_rst_n;
tri [23:0]  lcd_rgb;

wire        OS1;
wire        OS0;
wire        OS2;
wire        Convst;
wire        RD;
wire        RESET;
wire        Busy;
wire        cs;
wire        Range;
wire        Frstdata;
wire        DB0;
wire        DB1;
wire        DB2;
wire        DB3;
wire        DB4;
wire        DB5;
wire        DB6;
wire        DB7;
wire        DB8;
wire        DB9;
wire        DB10;
wire        DB11;
wire        DB12;
wire        DB13;
wire        DB14;
wire        DB15;

reg         panel_id_drive_en;
reg [23:0]  panel_id_drive_value;

wire [15:0] adc_db_bus;

wire        lcd_pclk_mon;
wire        frame_toggle_mon;
wire        swap_toggle_mon;
wire        wave_commit_toggle_mon;
wire [10:0] pixel_x_mon;
wire [10:0] pixel_y_mon;

reg         frame_toggle_d;
reg         swap_toggle_d;
reg         wave_commit_toggle_d;
reg  [10:0] pixel_x_d1;
reg  [10:0] pixel_y_d1;
integer     lcd_frame_count;
integer     lcd_swap_count;
integer     wave_commit_count;
integer     adc_frame_count;
reg         freq_units_pixels_seen;
reg         phase_units_pixels_seen;
reg [6:0]   freq_units_char_idx_center;
reg [6:0]   phase_units_char_idx_center;

// Drive LCD ID bits only during reset release so rd_id can lock a valid panel.
assign lcd_rgb = panel_id_drive_en ? panel_id_drive_value : 24'hzzzzzz;

// Map the ADC behavior model bus back onto main's DB[15:0] pins.
assign DB0  = adc_db_bus[0];
assign DB1  = adc_db_bus[1];
assign DB2  = adc_db_bus[2];
assign DB3  = adc_db_bus[3];
assign DB4  = adc_db_bus[4];
assign DB5  = adc_db_bus[5];
assign DB6  = adc_db_bus[6];
assign DB7  = adc_db_bus[7];
assign DB8  = adc_db_bus[8];
assign DB9  = adc_db_bus[9];
assign DB10 = adc_db_bus[10];
assign DB11 = adc_db_bus[11];
assign DB12 = adc_db_bus[12];
assign DB13 = adc_db_bus[13];
assign DB14 = adc_db_bus[14];
assign DB15 = adc_db_bus[15];

// Export key hierarchy taps so the TB can monitor text commit, frame edge and pixel scan position.
assign lcd_pclk_mon           = dut.u_lcd_rgb_char.lcd_pclk;
assign frame_toggle_mon       = dut.u_lcd_rgb_char.frame_done_toggle_w;
assign swap_toggle_mon        = dut.u_lcd_rgb_char.u_lcd_display.text_swap_ack_toggle_lcd;
assign wave_commit_toggle_mon = dut.u_lcd_rgb_char.u_lcd_display.text_result_commit_toggle;
assign pixel_x_mon            = dut.u_lcd_rgb_char.pixel_xpos_w;
assign pixel_y_mon            = dut.u_lcd_rgb_char.pixel_ypos_w;

// Instantiate the real top-level DUT.
main dut (
    .sys_clk    (sys_clk),
    .sys_rst_n  (sys_rst_n),
    .uart_rxd   (uart_rxd),
    .uart_txd   (),
    .touch_sda  (touch_sda),
    .touch_scl  (touch_scl),
    .touch_int  (touch_int),
    .touch_rst_n(touch_rst_n),
    .lcd_de     (lcd_de),
    .lcd_hs     (lcd_hs),
    .lcd_vs     (lcd_vs),
    .lcd_bl     (lcd_bl),
    .lcd_clk    (lcd_clk),
    .lcd_rst_n  (lcd_rst_n),
    .lcd_rgb    (lcd_rgb),
    .OS1        (OS1),
    .OS0        (OS0),
    .OS2        (OS2),
    .Convst     (Convst),
    .RD         (RD),
    .RESET      (RESET),
    .Busy       (Busy),
    .cs         (cs),
    .Range      (Range),
    .Frstdata   (Frstdata),
    .DB0        (DB0),
    .DB1        (DB1),
    .DB2        (DB2),
    .DB3        (DB3),
    .DB4        (DB4),
    .DB5        (DB5),
    .DB6        (DB6),
    .DB7        (DB7),
    .DB8        (DB8),
    .DB9        (DB9),
    .DB10       (DB10),
    .DB11       (DB11),
    .DB12       (DB12),
    .DB13       (DB13),
    .DB14       (DB14),
    .DB15       (DB15)
);

// Instantiate the AD7606 parallel-interface behavior model.
ad7606_adc_model u_ad7606_adc_model (
    .clk        (sys_clk),
    .rst_n      (sys_rst_n),
    .ad_reset   (RESET),
    .ad_convst  (Convst),
    .ad_cs_n    (cs),
    .ad_rd_n    (RD),
    .ad_busy    (Busy),
    .ad_frstdata(Frstdata),
    .ad_data    (adc_db_bus)
);

// Generate the system clock.
always #SYS_CLK_HALF_PERIOD_NS sys_clk = ~sys_clk;

// Apply reset, hold the LCD ID drive long enough for rd_id to sample, and initialize TB state.
initial begin
    sys_clk                    = 1'b0;
    sys_rst_n                  = 1'b0;
    uart_rxd                   = 1'b1;
    panel_id_drive_en          = 1'b1;
    panel_id_drive_value       = PANEL_ID_RGB_7016;
    frame_toggle_d             = 1'b0;
    swap_toggle_d              = 1'b0;
    wave_commit_toggle_d       = 1'b0;
    pixel_x_d1                 = 11'd0;
    pixel_y_d1                 = 11'd0;
    lcd_frame_count            = 0;
    lcd_swap_count             = 0;
    wave_commit_count          = 0;
    adc_frame_count            = 0;
    freq_units_pixels_seen     = 1'b0;
    phase_units_pixels_seen    = 1'b0;
    freq_units_char_idx_center = 7'd127;
    phase_units_char_idx_center = 7'd127;

    $display("[%0t] tb_main: start top-level simulation", $time);

    #1000;
    sys_rst_n = 1'b1;

    repeat (64) @(posedge sys_clk);
    panel_id_drive_en = 1'b0;
    $display("[%0t] tb_main: released LCD ID drive", $time);
end

// Report PLL lock and the internal rst_n used by the ADC/measurement chain.
always @(posedge sys_clk) begin
    if ($time < 2000000 || dut.locked !== 1'b1 || dut.rst_n !== 1'b1) begin
        if (($time % 200000) == 0)
            $display("[%0t] pll/rst: locked=%0d rst_n=%0d", $time, dut.locked, dut.rst_n);
    end
end

// Stop on timeout so the simulation cannot hang forever.
initial begin : watchdog
    #MAX_SIM_TIME_NS;
    $display("[%0t] tb_main: timeout, no sufficient LCD text swap observed", $time);
    $finish;
end

// End after several LCD-side packet swaps so multiple dynamic-text updates are observed by default.
initial begin : stop_after_target_swap
    wait (lcd_swap_count >= TARGET_LCD_SWAPS);
    repeat (4) @(posedge sys_clk);
    $display("[%0t] tb_main: reached target LCD swap count = %0d", $time, lcd_swap_count);
    $finish;
end

// Print one line each time the wave-domain text packet is committed.
always @(posedge sys_clk) begin
    if (dut.adc_frame_valid) begin
        adc_frame_count = adc_frame_count + 1;
        if (adc_frame_count <= 8 || (adc_frame_count % 128) == 0) begin
            $display("[%0t] adc frame %0d: AD1=%0d AD3=%0d u_valid=%0d i_valid=%0d startup_done=%0d",
                     $time,
                     adc_frame_count,
                     dut.AD_DATA_1,
                     dut.AD_DATA_3,
                     dut.adc_u_wave_sample_valid,
                     dut.adc_i_wave_sample_valid,
                     dut.adc_startup_wait_done);
        end
    end

    if (wave_commit_toggle_mon ^ wave_commit_toggle_d) begin
        wave_commit_count = wave_commit_count + 1;
        $display("[%0t] wave commit %0d: freq_valid=%0d freq_digits=%0d%0d%0d.%0d%0d phase_valid=%0d phase_neg=%0d phase_digits=%0d%0d%0d.%0d%0d",
                 $time,
                 wave_commit_count,
                 dut.u_lcd_rgb_char.u_lcd_display.freq_valid,
                 dut.u_lcd_rgb_char.u_lcd_display.freq_hundreds,
                 dut.u_lcd_rgb_char.u_lcd_display.freq_tens,
                 dut.u_lcd_rgb_char.u_lcd_display.freq_units,
                 dut.u_lcd_rgb_char.u_lcd_display.freq_decile,
                 dut.u_lcd_rgb_char.u_lcd_display.freq_percentiles,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_valid,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_neg,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_hundreds,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_tens,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_units,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_decile,
                 dut.u_lcd_rgb_char.u_lcd_display.phase_percentiles);
    end

    wave_commit_toggle_d = wave_commit_toggle_mon;
end

// Align the scanned pixel coordinates with text_pixel_on and summarize one frame of the two units-digit cells.
always @(posedge lcd_pclk_mon or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        frame_toggle_d              <= 1'b0;
        swap_toggle_d               <= 1'b0;
        pixel_x_d1                  <= 11'd0;
        pixel_y_d1                  <= 11'd0;
        freq_units_pixels_seen      <= 1'b0;
        phase_units_pixels_seen     <= 1'b0;
        freq_units_char_idx_center  <= 7'd127;
        phase_units_char_idx_center <= 7'd127;
    end else begin
        if ((pixel_x_d1 >= FREQ_UNITS_X0) && (pixel_x_d1 < FREQ_UNITS_X1) &&
            (pixel_y_d1 >= FREQ_UNITS_Y0) && (pixel_y_d1 < FREQ_UNITS_Y1)) begin
            if (dut.u_lcd_rgb_char.u_lcd_display.text_pixel_on)
                freq_units_pixels_seen <= 1'b1;
        end

        if ((pixel_x_d1 >= PHASE_UNITS_X0) && (pixel_x_d1 < PHASE_UNITS_X1) &&
            (pixel_y_d1 >= PHASE_UNITS_Y0) && (pixel_y_d1 < PHASE_UNITS_Y1)) begin
            if (dut.u_lcd_rgb_char.u_lcd_display.text_pixel_on)
                phase_units_pixels_seen <= 1'b1;
        end

        if ((pixel_x_mon == FREQ_UNITS_X_CENTER) && (pixel_y_mon == FREQ_UNITS_Y_CENTER))
            freq_units_char_idx_center <= dut.u_lcd_rgb_char.u_lcd_display.text_char_idx;

        if ((pixel_x_mon == PHASE_UNITS_X_CENTER) && (pixel_y_mon == PHASE_UNITS_Y_CENTER))
            phase_units_char_idx_center <= dut.u_lcd_rgb_char.u_lcd_display.text_char_idx;

        if (swap_toggle_mon ^ swap_toggle_d) begin
            lcd_swap_count = lcd_swap_count + 1;
            $display("[%0t] lcd swap %0d: freq_valid_lcd=%0d freq_units_lcd=%0d phase_valid_lcd=%0d phase_units_lcd=%0d pending=%0d",
                     $time,
                     lcd_swap_count,
                     dut.u_lcd_rgb_char.u_lcd_display.freq_valid_lcd,
                     dut.u_lcd_rgb_char.u_lcd_display.freq_units_lcd,
                     dut.u_lcd_rgb_char.u_lcd_display.phase_valid_lcd,
                     dut.u_lcd_rgb_char.u_lcd_display.phase_units_lcd,
                     dut.u_lcd_rgb_char.u_lcd_display.text_commit_pending_lcd);
        end

        if (frame_toggle_mon ^ frame_toggle_d) begin
            lcd_frame_count = lcd_frame_count + 1;
            $display("[%0t] lcd frame %0d: freq_valid_lcd=%0d freq_units_lcd=%0d freq_char_idx=%0d freq_pixels=%0d | phase_valid_lcd=%0d phase_units_lcd=%0d phase_char_idx=%0d phase_pixels=%0d",
                     $time,
                     lcd_frame_count,
                     dut.u_lcd_rgb_char.u_lcd_display.freq_valid_lcd,
                     dut.u_lcd_rgb_char.u_lcd_display.freq_units_lcd,
                     freq_units_char_idx_center,
                     freq_units_pixels_seen,
                     dut.u_lcd_rgb_char.u_lcd_display.phase_valid_lcd,
                     dut.u_lcd_rgb_char.u_lcd_display.phase_units_lcd,
                     phase_units_char_idx_center,
                     phase_units_pixels_seen);

            if (dut.u_lcd_rgb_char.u_lcd_display.freq_valid_lcd &&
                (dut.u_lcd_rgb_char.u_lcd_display.freq_units_lcd <= 8'd9) &&
                (freq_units_char_idx_center == 7'd127))
                $display("[%0t] WARN: Frequency units digit is valid but text_char_idx is blank", $time);

            if (dut.u_lcd_rgb_char.u_lcd_display.phase_valid_lcd &&
                (dut.u_lcd_rgb_char.u_lcd_display.phase_units_lcd <= 8'd9) &&
                (phase_units_char_idx_center == 7'd127))
                $display("[%0t] WARN: Phase units digit is valid but text_char_idx is blank", $time);

            freq_units_pixels_seen      <= 1'b0;
            phase_units_pixels_seen     <= 1'b0;
            freq_units_char_idx_center  <= 7'd127;
            phase_units_char_idx_center <= 7'd127;
        end

        pixel_x_d1    <= pixel_x_mon;
        pixel_y_d1    <= pixel_y_mon;
        frame_toggle_d <= frame_toggle_mon;
        swap_toggle_d  <= swap_toggle_mon;
    end
end

endmodule
