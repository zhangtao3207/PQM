`include "touch_state.v"

/*
 * 模块: touch_top
 * 功能:
 *   触摸子系统顶层，连接 I2C 驱动、协议层和触摸状态机。
 *
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效复位信号。
 *   lcd_id: LCD 面板 ID。
 *
 * 输出:
 *   touch_rst_n: 触摸芯片低有效复位输出。
 *   touch_scl: 触摸 I2C SCL 输出。
 *   data: 触摸坐标打包数据。
 *   touch_pressed: 触摸按下状态。
 *   touch_unpressed: 触摸释放状态。
 *   touch_click: 触摸点击脉冲。
 *   touch_long_press: 触摸长按脉冲。
 *   touch_drag: 触摸拖拽脉冲。
 *   touch_click_state: 触摸点击状态位。
 *   touch_long_state: 触摸长按状态位。
 *   touch_drag_state: 触摸拖拽状态位。
 *   touch_start_x: 触摸起点 X 坐标。
 *   touch_start_y: 触摸起点 Y 坐标。
 *   touch_end_x: 触摸终点 X 坐标。
 *   touch_end_y: 触摸终点 Y 坐标。
 *   touch_press_time_ms: 当前按压持续时间，单位 ms。
 *
 * 双向:
 *   touch_int: 触摸中断/握手双向引脚。
 *   touch_sda: 触摸 I2C SDA 双向信号。
 */
module touch_top(
    input             clk        ,
    input             rst_n      ,

    output            touch_rst_n,
    inout             touch_int  ,
    output            touch_scl  ,
    inout             touch_sda,

    input     [15:0]  lcd_id     ,
    output    [31:0]  data       ,

    output            touch_pressed    ,
    output            touch_unpressed  ,
    output            touch_click      ,
    output            touch_long_press ,
    output            touch_drag       ,
    output            touch_click_state,
    output            touch_long_state ,
    output            touch_drag_state ,
    output    [15:0]  touch_start_x    ,
    output    [15:0]  touch_start_y    ,
    output    [15:0]  touch_end_x      ,
    output    [15:0]  touch_end_y      ,
    output    [15:0]  touch_press_time_ms
);

// 触摸链顶层公共参数。
parameter CLK_FREQ    = 50_000_000   ;
parameter I2C_FREQ    = 250_000      ;
parameter REG_NUM_WID = 8            ;

wire  [6:0]             slave_addr     ;
wire                    i2c_exec       ;
wire                    i2c_rh_wl      ;
wire  [15:0]            i2c_addr       ;
wire  [7:0]             i2c_data_w     ;
wire                    bit_ctrl       ;
wire  [REG_NUM_WID-1:0] reg_num        ;
wire  [7:0]             i2c_data_r     ;
wire                    i2c_done       ;
wire                    once_byte_done ;
wire                    i2c_ack        ;
wire                    dri_clk        ;
wire                    touch_valid    ;

// 通用 I2C 事务层。
i2c_dri #(
    .CLK_FREQ      (CLK_FREQ     ),
    .I2C_FREQ      (I2C_FREQ     ),
    .WIDTH         (REG_NUM_WID  )
    )
    u_i2c_dri(
    .clk           (clk          ),
    .rst_n         (rst_n        ),

    .slave_addr    (slave_addr    ),
    .i2c_exec      (i2c_exec      ),
    .i2c_rh_wl     (i2c_rh_wl     ),
    .i2c_addr      (i2c_addr      ),
    .i2c_data_w    (i2c_data_w    ),
    .bit_ctrl      (bit_ctrl      ),
    .reg_num       (reg_num       ),
    .i2c_data_r    (i2c_data_r    ),
    .i2c_done      (i2c_done      ),
    .once_byte_done(once_byte_done),
    .scl           (touch_scl     ),
    .sda           (touch_sda     ),
    .ack           (i2c_ack       ),

    .dri_clk       (dri_clk       )
    );

// 触摸芯片协议层。
touch_dri #(
    .WIDTH         (REG_NUM_WID   )
     )
    u_touch_dri(
    .clk           (dri_clk       ),
    .rst_n         (rst_n         ),

    .slave_addr    (slave_addr    ),
    .i2c_exec      (i2c_exec      ),
    .i2c_rh_wl     (i2c_rh_wl     ),
    .i2c_addr      (i2c_addr      ),
    .i2c_data_w    (i2c_data_w    ),
    .bit_ctrl      (bit_ctrl      ),
    .reg_num       (reg_num       ),

    .i2c_data_r    (i2c_data_r    ),
    .i2c_ack       (i2c_ack       ),
    .i2c_done      (i2c_done      ),
    .once_byte_done(once_byte_done),

    .lcd_id        (lcd_id        ),
    .data          (data          ),
    .touch_valid   (touch_valid   ),
    .touch_rst_n   (touch_rst_n   ),
    .touch_int     (touch_int     )
    );

// 高层手势状态层。
touch_state #(
    .CLK_FREQ_HZ   (I2C_FREQ * 4)
) u_touch_state(
    .clk               (dri_clk             ),
    .rst_n             (rst_n               ),
    .touch_valid       (touch_valid         ),
    .touch_data        (data                ),
    .pressed           (touch_pressed       ),
    .unpressed         (touch_unpressed     ),
    .click_pulse       (touch_click         ),
    .long_press_pulse  (touch_long_press    ),
    .drag_pulse        (touch_drag          ),
    .click_state       (touch_click_state   ),
    .long_press_state  (touch_long_state    ),
    .drag_state        (touch_drag_state    ),
    .start_x           (touch_start_x       ),
    .start_y           (touch_start_y       ),
    .end_x             (touch_end_x         ),
    .end_y             (touch_end_y         ),
    .press_time_ms     (touch_press_time_ms )
);

endmodule
