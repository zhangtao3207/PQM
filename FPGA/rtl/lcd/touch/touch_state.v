/*
 * 模块: touch_state
 * 功能:
 *   解析触摸坐标有效信号和坐标数据，生成按下、释放、点击、长按和拖拽事件。
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效异步复位信号。
 *   touch_valid: 原始触摸坐标有效标志。
 *   touch_data: 原始触摸坐标打包数据，高 16 位为 X 坐标，低 16 位为 Y 坐标。
 * 输出:
 *   pressed: 消抖后的触摸按下状态。
 *   unpressed: 消抖后的触摸释放状态。
 *   click_pulse: 释放时判定为点击事件的单周期脉冲。
 *   long_press_pulse: 按压超过长按阈值时产生的单周期脉冲。
 *   drag_pulse: 释放时判定为拖拽事件的单周期脉冲。
 *   click_state: 当前周期点击事件状态。
 *   long_press_state: 当前按压是否已经进入长按状态。
 *   drag_state: 当前按压是否已经进入拖拽状态。
 *   start_x: 本次触摸稳定后的起点 X 坐标。
 *   start_y: 本次触摸稳定后的起点 Y 坐标。
 *   end_x: 本次触摸最新终点 X 坐标。
 *   end_y: 本次触摸最新终点 Y 坐标。
 *   press_time_ms: 当前按压持续时间，单位为 ms。
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

// 由按下状态直接生成释放状态，供上层显示或状态机使用。
assign unpressed = ~pressed;

// 在 clk 域对原始 touch_valid 做消抖，并锁存稳定触摸期间的最新坐标。
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

// 在 clk 域根据消抖后的触摸边沿和坐标变化，生成点击、长按和拖拽事件。
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
                // 使用第一个稳定采样点作为手势起点，避免旧坐标导致误判。
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
            // 释放后清空持续状态，等待下一次触摸重新判定。
            long_press_state <= 1'b0;
            drag_state       <= 1'b0;
            start_locked     <= 1'b0;
            drag_latched     <= 1'b0;
        end
    end
end

endmodule