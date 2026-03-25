`ifndef TOUCH_STATE_V
`define TOUCH_STATE_V
/*
 * Module: touch_state
 * 功能:
 *   基于触摸坐标与触摸有效信号，输出按下/松开/点击/长按/拖动状态。
 *   - 长按阈值默认 750ms
 *   - 拖动判定默认位移阈值 8 像素（曼哈顿距离）
 */
module touch_state #(
    parameter CLK_FREQ_HZ      = 50_000_000,
    parameter LONG_PRESS_MS    = 750,
    parameter DEBOUNCE_MS      = 20,
    parameter DRAG_THRESH_PX   = 16
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         touch_valid,
    input  wire [31:0]  touch_data,

    output reg          pressed,
    output wire         unpressed,
    output reg          click_pulse,
    output reg          long_press_pulse,
    output reg          drag_pulse,
    output reg          click_state,
    output reg          long_press_state,
    output reg          drag_state,

    output reg  [15:0]  start_x,
    output reg  [15:0]  start_y,
    output reg  [15:0]  end_x,
    output reg  [15:0]  end_y,
    output reg  [15:0]  press_time_ms
);

localparam integer MS_DIV             = CLK_FREQ_HZ / 1000;
localparam integer DB_TICKS           = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
localparam integer LONG_PRESS_TICKS   = LONG_PRESS_MS;

reg         touch_valid_filt;
reg         touch_valid_filt_d0;
reg [31:0]  debounce_cnt;
reg [31:0]  touch_data_d0;
reg [31:0]  ms_div_cnt;
reg [15:0]  hold_ms_cnt;
reg         long_press_latched;
reg         start_locked;
reg         drag_latched;

wire [15:0] cur_x = touch_data_d0[31:16];
wire [15:0] cur_y = touch_data_d0[15:0];

wire press_rise_fix = touch_valid_filt & ~touch_valid_filt_d0;
wire press_fall = ~touch_valid_filt & touch_valid_filt_d0;

wire [15:0] dx = (cur_x >= start_x) ? (cur_x - start_x) : (start_x - cur_x);
wire [15:0] dy = (cur_y >= start_y) ? (cur_y - start_y) : (start_y - cur_y);
wire [16:0] drag_dist = {1'b0, dx} + {1'b0, dy};
wire        drag_hit  = (drag_dist >= DRAG_THRESH_PX);

assign unpressed = ~pressed;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        touch_valid_filt    <= 1'b0;
        touch_valid_filt_d0 <= 1'b0;
        debounce_cnt        <= 32'd0;
        touch_data_d0      <= 32'd0;
    end
    else begin
        touch_valid_filt_d0 <= touch_valid_filt;

        if(touch_valid == touch_valid_filt) begin
            debounce_cnt <= 32'd0;
        end
        else if(debounce_cnt >= DB_TICKS - 1) begin
            touch_valid_filt <= touch_valid;
            debounce_cnt     <= 32'd0;
        end
        else begin
            debounce_cnt <= debounce_cnt + 32'd1;
        end

        if(touch_valid_filt)
            touch_data_d0  <= touch_data;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pressed            <= 1'b0;
        click_pulse        <= 1'b0;
        long_press_pulse   <= 1'b0;
        drag_pulse         <= 1'b0;
        click_state        <= 1'b0;
        long_press_state   <= 1'b0;
        drag_state         <= 1'b0;
        start_x            <= 16'd0;
        start_y            <= 16'd0;
        end_x              <= 16'd0;
        end_y              <= 16'd0;
        press_time_ms      <= 16'd0;
        ms_div_cnt         <= 32'd0;
        hold_ms_cnt        <= 16'd0;
        long_press_latched <= 1'b0;
        start_locked       <= 1'b0;
        drag_latched       <= 1'b0;
    end
    else begin
        click_pulse      <= 1'b0;
        long_press_pulse <= 1'b0;
        drag_pulse       <= 1'b0;
        click_state      <= 1'b0;

        if(press_rise_fix) begin
            pressed            <= 1'b1;
            start_x            <= 16'd0;
            start_y            <= 16'd0;
            end_x              <= 16'd0;
            end_y              <= 16'd0;
            press_time_ms      <= 16'd0;
            hold_ms_cnt        <= 16'd0;
            ms_div_cnt         <= 32'd0;
            long_press_latched <= 1'b0;
            click_state        <= 1'b0;
            long_press_state   <= 1'b0;
            drag_state         <= 1'b0;
            start_locked       <= 1'b0;
            drag_latched       <= 1'b0;
        end
        else if(touch_valid_filt_d0) begin
            pressed <= 1'b1;
            if(!start_locked) begin
                // Use first stable sampled point as gesture start to avoid stale-coordinate misjudge.
                start_x      <= cur_x;
                start_y      <= cur_y;
                end_x        <= cur_x;
                end_y        <= cur_y;
                start_locked <= 1'b1;
            end
            else begin
                end_x <= cur_x;
                end_y <= cur_y;
                if(drag_hit)
                    drag_latched <= 1'b1;
                drag_state <= (drag_latched | drag_hit);
            end

            if(ms_div_cnt == MS_DIV - 1) begin
                ms_div_cnt <= 32'd0;
                hold_ms_cnt <= hold_ms_cnt + 16'd1;
                press_time_ms <= hold_ms_cnt + 16'd1;

                if((hold_ms_cnt + 16'd1 >= LONG_PRESS_TICKS) && !long_press_latched) begin
                    long_press_latched <= 1'b1;
                    long_press_pulse   <= 1'b1;
                    long_press_state   <= 1'b1;
                end
            end
            else begin
                ms_div_cnt <= ms_div_cnt + 32'd1;
            end
        end

        if(press_fall) begin
            pressed <= 1'b0;
            if(drag_latched) begin
                drag_pulse <= 1'b1;
            end
            else if(!long_press_latched) begin
                click_pulse <= 1'b1;
                click_state <= 1'b1;
            end
            // Return to unpressed state after release.
            long_press_state <= 1'b0;
            drag_state       <= 1'b0;
            start_locked     <= 1'b0;
            drag_latched     <= 1'b0;
        end
    end
end

endmodule
`endif
