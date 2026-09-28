`timescale 1ns / 1ps

/*
 * 模块名称：pqm_touch_iobuf
 * 功能说明：把 PS I2C EMIO 三态信号和 GPIO EMIO 映射到触摸面板及物理按键。
 * 输入端口：
 *   ps_i2c_scl_o：PS I2C 时钟输出值。
 *   ps_i2c_scl_t：PS I2C 时钟三态控制，高电平释放总线。
 *   ps_i2c_sda_o：PS I2C 数据输出值。
 *   ps_i2c_sda_t：PS I2C 数据三态控制，高电平释放总线。
 *   ps_gpio_o：PS GPIO EMIO 输出总线。
 *   touch_int：触摸面板中断输入。
 *   key0：物理回退按键输入。
 * 输出端口：
 *   ps_i2c_scl_i：送回 PS 的 I2C 时钟电平。
 *   ps_i2c_sda_i：送回 PS 的 I2C 数据电平。
 *   ps_gpio_i：送回 PS 的 GPIO EMIO 输入总线。
 *   touch_rst_n：由 PS GPIO0 驱动的触摸芯片低有效复位。
 * 双向端口：
 *   touch_scl：触摸面板 I2C 时钟双向线。
 *   touch_sda：触摸面板 I2C 数据双向线。
 */
module pqm_touch_iobuf (
    input  wire        ps_i2c_scl_o,
    input  wire        ps_i2c_scl_t,
    output wire        ps_i2c_scl_i,
    input  wire        ps_i2c_sda_o,
    input  wire        ps_i2c_sda_t,
    output wire        ps_i2c_sda_i,
    input  wire [63:0] ps_gpio_o,
    output wire [63:0] ps_gpio_i,
    inout  wire        touch_scl,
    inout  wire        touch_sda,
    input  wire        touch_int,
    output wire        touch_rst_n,
    input  wire        key0
);

// 只为实际使用的触摸时钟引脚实例化开漏 IOBUF。
IOBUF u_touch_scl_iobuf (
    .I(ps_i2c_scl_o), .T(ps_i2c_scl_t),
    .O(ps_i2c_scl_i), .IO(touch_scl)
);

// 只为实际使用的触摸数据引脚实例化开漏 IOBUF。
IOBUF u_touch_sda_iobuf (
    .I(ps_i2c_sda_o), .T(ps_i2c_sda_t),
    .O(ps_i2c_sda_i), .IO(touch_sda)
);

// GPIO0 单向驱动触摸复位输出。
assign touch_rst_n = ps_gpio_o[0];

// 仅使用 GPIO0 至 GPIO2，其余 EMIO 输入固定为低电平。
assign ps_gpio_i = {61'd0, key0, touch_int, touch_rst_n};

endmodule
