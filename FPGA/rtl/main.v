`timescale 1ns / 1ps

/*
 * 模块名称：main
 * 功能说明：PQM SoC顶层，连接PL采集测量核心、Zynq PS、共享内存、DMA和PS帧缓存视频。
 * 输入端口：
 *   sys_clk：PL 采集和测量 50 MHz 时钟。
 *   sys_rst_n：PL 低有效系统复位。
 *   key0：送入PS GPIO的物理按键。
 *   uart_rxd：保留的板级串口输入引脚，新架构不在PL中处理。
 *   Busy：AD7606 忙输入。
 *   Frstdata：AD7606 首数据输入。
 *   DB0：AD7606 数据位 0。
 *   DB1：AD7606 数据位 1。
 *   DB2：AD7606 数据位 2。
 *   DB3：AD7606 数据位 3。
 *   DB4：AD7606 数据位 4。
 *   DB5：AD7606 数据位 5。
 *   DB6：AD7606 数据位 6。
 *   DB7：AD7606 数据位 7。
 *   DB8：AD7606 数据位 8。
 *   DB9：AD7606 数据位 9。
 *   DB10：AD7606 数据位 10。
 *   DB11：AD7606 数据位 11。
 *   DB12：AD7606 数据位 12。
 *   DB13：AD7606 数据位 13。
 *   DB14：AD7606 数据位 14。
 *   DB15：AD7606 数据位 15。
 * 输出端口：
 *   uart_txd：保留的板级串口输出，PL固定为空闲高电平。
 *   led：告警 LED 输出。
 *   buzzer：告警蜂鸣器输出。
 *   touch_rst_n：触摸控制器低有效复位。
 *   lcd_de：LCD 数据有效输出。
 *   lcd_hs：LCD 行同步输出。
 *   lcd_vs：LCD 场同步输出。
 *   lcd_bl：LCD 背光使能输出。
 *   lcd_clk：LCD 像素时钟输出。
 *   lcd_rst_n：LCD 低有效复位输出。
 *   OS1：AD7606 过采样配置位 1。
 *   OS0：AD7606 过采样配置位 0。
 *   OS2：AD7606 过采样配置位 2。
 *   Convst：AD7606 转换启动输出。
 *   RD：AD7606 读选通输出。
 *   RESET：AD7606 复位输出。
 *   cs：AD7606 片选输出。
 *   Range：AD7606 量程选择输出。
 * 双向端口：
 *   touch_sda：触摸 I2C 数据线。
 *   touch_scl：触摸 I2C 时钟线。
 *   touch_int：触摸中断线。
 *   lcd_rgb：由PS视频通路驱动的LCD RGB888数据线。
 *   DDR_*：Zynq PS DDR3 专用接口。
 *   FIXED_IO_*：Zynq PS MIO、时钟和复位专用接口。
 */
module main (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        key0,
    input  wire        uart_rxd,
    output wire        uart_txd,
    output wire        led,
    output wire        buzzer,
    inout  wire        touch_sda,
    inout  wire        touch_scl,
    inout  wire        touch_int,
    output wire        touch_rst_n,
    output wire        lcd_de,
    output wire        lcd_hs,
    output wire        lcd_vs,
    output wire        lcd_bl,
    output wire        lcd_clk,
    output wire        lcd_rst_n,
    inout  wire [23:0] lcd_rgb,
    output wire        OS1,
    output wire        OS0,
    output wire        OS2,
    output wire        Convst,
    output wire        RD,
    output wire        RESET,
    input  wire        Busy,
    output wire        cs,
    output wire        Range,
    input  wire        Frstdata,
    input  wire        DB0,
    input  wire        DB1,
    input  wire        DB2,
    input  wire        DB3,
    input  wire        DB4,
    input  wire        DB5,
    input  wire        DB6,
    input  wire        DB7,
    input  wire        DB8,
    input  wire        DB9,
    input  wire        DB10,
    input  wire        DB11,
    input  wire        DB12,
    input  wire        DB13,
    input  wire        DB14,
    input  wire        DB15,
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

wire [15:0] adc_u_sample;
wire [15:0] adc_i_sample;
wire        adc_frame_valid;
wire        adc_timeout;
wire        pl_measure_clk;
wire        pl_measure_resetn;
wire [511:0] snapshot_words;
wire        snapshot_commit_toggle;
wire        pl_harmonic_valid;
wire        pl_harmonic_ready;
wire        pl_harmonic_last;
wire [8:0]  pl_harmonic_index;
wire [31:0] pl_harmonic_u_ratio;
wire [31:0] pl_harmonic_i_ratio;
wire [31:0] pl_harmonic_phase;
wire [31:0] pl_harmonic_flags;

wire        sample_axis_ready;
wire [63:0] sample_axis_data;
wire        sample_axis_valid;
wire        sample_axis_last;
wire [31:0] sample_source_sequence;
wire [31:0] sample_drop_count;

wire [13:0] bram_addr;
wire [31:0] bram_wrdata;
wire [31:0] bram_rddata;
wire [3:0]  bram_we;
wire        bram_en;
wire        snapshot_bridge_ready;
wire        harmonic_start_ready;
wire        harmonic_bridge_ready;
wire [31:0] snapshot_sequence;
wire [31:0] harmonic_generation;
wire        active_harmonic_bank;
wire        command_valid;
wire [31:0] command_code;
wire [31:0] command_argument;
wire [31:0] command_sequence;
wire        command_response_ready;
wire        command_response_valid;
wire [31:0] command_response;
wire        ps_low_range_active;
wire        harmonic_frame_start;
wire        snapshot_commit;
reg         snapshot_commit_d1;
reg         snapshot_pending;

wire [15:0] ps_rgb565_data;
wire [1:0]  ps_rgb565_keep;
wire        ps_rgb565_last;
wire        ps_rgb565_ready;
wire        ps_rgb565_user;
wire        ps_rgb565_valid;
wire [23:0] ps_rgb888_data;
wire        ps_rgb888_last;
wire        ps_rgb888_ready;
wire        ps_rgb888_user;
wire        ps_rgb888_valid;
wire        ps_pixel_clk;
wire [0:0]  ps_pixel_resetn;
wire        ps_lcd_active_video;
wire [23:0] ps_lcd_data;
wire        ps_lcd_field;
wire        ps_lcd_hblank;
wire        ps_lcd_hsync;
wire        ps_lcd_vblank;
wire        ps_lcd_vsync;
wire        ps_axi_clk;
wire [0:0]  ps_axi_resetn;
wire [63:0] ps_touch_gpio_i;
wire [63:0] ps_touch_gpio_o;
wire [63:0] ps_touch_gpio_t;
wire        ps_touch_i2c_scl_i;
wire        ps_touch_i2c_scl_o;
wire        ps_touch_i2c_scl_t;
wire        ps_touch_i2c_sda_i;
wire        ps_touch_i2c_sda_o;
wire        ps_touch_i2c_sda_t;
wire        snapshot_irq;
wire        harmonic_irq;
reg  [31:0] snapshot_sequence_d1;
reg  [31:0] harmonic_generation_d1;

// PL核心负责AD7606采集、测量、FFT和告警，不再包含显示、触摸或UART协议。
pqm_pl_core u_pqm_pl_core (
    .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
    .ps_low_range_active(ps_low_range_active),
    .led(led), .buzzer(buzzer),
    .OS1(OS1), .OS0(OS0), .OS2(OS2), .Convst(Convst), .RD(RD), .RESET(RESET),
    .Busy(Busy), .cs(cs), .Range(Range), .Frstdata(Frstdata),
    .DB0(DB0), .DB1(DB1), .DB2(DB2), .DB3(DB3),
    .DB4(DB4), .DB5(DB5), .DB6(DB6), .DB7(DB7),
    .DB8(DB8), .DB9(DB9), .DB10(DB10), .DB11(DB11),
    .DB12(DB12), .DB13(DB13), .DB14(DB14), .DB15(DB15),
    .ps_adc_u_sample(adc_u_sample), .ps_adc_i_sample(adc_i_sample),
    .ps_adc_frame_valid(adc_frame_valid), .ps_adc_timeout(adc_timeout),
    .ps_pl_clk(pl_measure_clk), .ps_pl_reset_n(pl_measure_resetn),
    .ps_snapshot_words(snapshot_words), .ps_snapshot_commit_toggle(snapshot_commit_toggle),
    .ps_harmonic_valid(pl_harmonic_valid), .ps_harmonic_ready(pl_harmonic_ready),
    .ps_harmonic_last(pl_harmonic_last), .ps_harmonic_index(pl_harmonic_index),
    .ps_harmonic_u_ratio(pl_harmonic_u_ratio), .ps_harmonic_i_ratio(pl_harmonic_i_ratio),
    .ps_harmonic_phase(pl_harmonic_phase), .ps_harmonic_flags(pl_harmonic_flags)
);

// 原始 ADC 样本流：DMA 反压时丢弃新样本，不反压旧 PL 采集链路。
pqm_axis_sample_stream u_pqm_axis_sample_stream (
    .clk(pl_measure_clk), .rst_n(pl_measure_resetn), .sample_valid(adc_frame_valid),
    .u_sample(adc_u_sample), .i_sample(adc_i_sample),
    .source_sequence(sample_source_sequence), .drop_count(sample_drop_count),
    .m_axis_tdata(sample_axis_data), .m_axis_tvalid(sample_axis_valid),
    .m_axis_tready(sample_axis_ready), .m_axis_tlast(sample_axis_last)
);

// 快照 toggle 转为可积压的提交请求，谐波发布期间不会丢失最近一次更新。
always @(posedge pl_measure_clk) begin
    if (!pl_measure_resetn) begin
        snapshot_commit_d1 <= 1'b0;
        snapshot_pending   <= 1'b0;
    end else begin
        snapshot_commit_d1 <= snapshot_commit_toggle;
        if (snapshot_commit_toggle != snapshot_commit_d1) begin
            snapshot_pending <= 1'b1;
        end else if (snapshot_pending && snapshot_bridge_ready) begin
            snapshot_pending <= 1'b0;
        end
    end
end

// 记录已发布代数，生成送入 PS GIC 的单拍事件。
always @(posedge pl_measure_clk) begin
    if (!pl_measure_resetn) begin
        snapshot_sequence_d1   <= 32'd0;
        harmonic_generation_d1 <= 32'd0;
    end else begin
        snapshot_sequence_d1   <= snapshot_sequence;
        harmonic_generation_d1 <= harmonic_generation;
    end
end

// 有积压快照且桥为空闲时发出一次提交脉冲。
assign snapshot_commit = snapshot_pending && snapshot_bridge_ready;

// 谐波 0 号条目先启动非活动 bank，流保持到桥返回 ready。
assign harmonic_frame_start = pl_harmonic_valid
                            && (pl_harmonic_index == 9'd0)
                            && harmonic_start_ready;

// FFT谐波流仅在共享内存桥允许时完成握手。
assign pl_harmonic_ready = harmonic_bridge_ready;

// 标量序号变化生成快照中断脉冲。
assign snapshot_irq = (snapshot_sequence != snapshot_sequence_d1);

// 谐波代数变化生成谐波中断脉冲。
assign harmonic_irq = (harmonic_generation != harmonic_generation_d1);

// 共享内存桥使用 BRAM 端口 B，串行发布测量结果和命令响应。
pqm_shared_memory_bridge u_pqm_shared_memory_bridge (
    .clk(pl_measure_clk), .rst_n(pl_measure_resetn),
    .snapshot_commit(snapshot_commit), .snapshot_ready(snapshot_bridge_ready),
    .snapshot_words(snapshot_words),
    .harmonic_frame_start(harmonic_frame_start), .harmonic_start_ready(harmonic_start_ready),
    .harmonic_valid(pl_harmonic_valid), .harmonic_ready(harmonic_bridge_ready),
    .harmonic_index(pl_harmonic_index), .harmonic_u_ratio(pl_harmonic_u_ratio),
    .harmonic_i_ratio(pl_harmonic_i_ratio), .harmonic_phase(pl_harmonic_phase),
    .harmonic_flags(pl_harmonic_flags),
    .command_valid(command_valid), .command_code(command_code),
    .command_argument(command_argument), .command_sequence(command_sequence),
    .command_response_valid(command_response_valid), .command_response_ready(command_response_ready),
    .command_response(command_response),
    .snapshot_sequence(snapshot_sequence), .harmonic_generation(harmonic_generation),
    .active_harmonic_bank(active_harmonic_bank),
    .bram_addr(bram_addr), .bram_wrdata(bram_wrdata), .bram_we(bram_we),
    .bram_en(bram_en), .bram_rddata(bram_rddata)
);

// 解析 PS 量程命令，并把已确认的档位直接送入纯测量核心。
pqm_range_command_controller u_pqm_range_command_controller (
    .clk(pl_measure_clk),
    .rst_n(pl_measure_resetn),
    .command_valid(command_valid),
    .command_code(command_code),
    .command_argument(command_argument),
    .response_valid(command_response_valid),
    .response_ready(command_response_ready),
    .response(command_response),
    .low_range_active(ps_low_range_active)
);

// VDMA RGB565 输出扩展为 AXI4-Stream Video RGB888。
pqm_axis_rgb565_to_rgb888 u_pqm_axis_rgb565_to_rgb888 (
    .clk(ps_pixel_clk), .rst_n(ps_pixel_resetn[0]),
    .s_axis_tdata(ps_rgb565_data), .s_axis_tvalid(ps_rgb565_valid),
    .s_axis_tready(ps_rgb565_ready), .s_axis_tuser(ps_rgb565_user),
    .s_axis_tlast(ps_rgb565_last), .m_axis_tdata(ps_rgb888_data),
    .m_axis_tvalid(ps_rgb888_valid), .m_axis_tready(ps_rgb888_ready),
    .m_axis_tuser(ps_rgb888_user), .m_axis_tlast(ps_rgb888_last)
);

// 直接实例化 BD 模块，保留 EMIO I/O/T 信号并避免为未使用 GPIO 插入 IOBUF。
pqm_ps u_pqm_ps (
    .DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n),
    .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke),
    .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm), .DDR_dq(DDR_dq),
    .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
    .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
    .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
    .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
    .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
    .LCD_VIDEO_active_video(ps_lcd_active_video), .LCD_VIDEO_data(ps_lcd_data),
    .LCD_VIDEO_field(ps_lcd_field), .LCD_VIDEO_hblank(ps_lcd_hblank),
    .LCD_VIDEO_hsync(ps_lcd_hsync), .LCD_VIDEO_vblank(ps_lcd_vblank),
    .LCD_VIDEO_vsync(ps_lcd_vsync),
    .M_AXIS_VIDEO_RGB565_tdata(ps_rgb565_data), .M_AXIS_VIDEO_RGB565_tkeep(ps_rgb565_keep),
    .M_AXIS_VIDEO_RGB565_tlast(ps_rgb565_last), .M_AXIS_VIDEO_RGB565_tready(ps_rgb565_ready),
    .M_AXIS_VIDEO_RGB565_tuser(ps_rgb565_user), .M_AXIS_VIDEO_RGB565_tvalid(ps_rgb565_valid),
    .PIXEL_ARESETN(ps_pixel_resetn), .PIXEL_CLK(ps_pixel_clk),
    .PL_AXI_ARESETN(ps_axi_resetn), .PL_AXI_CLK(ps_axi_clk),
    .PL_SHARED_BRAM_addr({18'd0, bram_addr}), .PL_SHARED_BRAM_clk(pl_measure_clk),
    .PL_SHARED_BRAM_din(bram_wrdata), .PL_SHARED_BRAM_dout(bram_rddata),
    .PL_SHARED_BRAM_en(bram_en), .PL_SHARED_BRAM_rst(!pl_measure_resetn), .PL_SHARED_BRAM_we(bram_we),
    .SAMPLE_AXIS_ARESETN(pl_measure_resetn), .SAMPLE_AXIS_CLK(pl_measure_clk),
    .S_AXIS_SAMPLES_tdata(sample_axis_data), .S_AXIS_SAMPLES_tkeep(8'hFF),
    .S_AXIS_SAMPLES_tlast(sample_axis_last), .S_AXIS_SAMPLES_tready(sample_axis_ready),
    .S_AXIS_SAMPLES_tvalid(sample_axis_valid),
    .S_AXIS_VIDEO_RGB888_tdata(ps_rgb888_data), .S_AXIS_VIDEO_RGB888_tlast(ps_rgb888_last),
    .S_AXIS_VIDEO_RGB888_tready(ps_rgb888_ready), .S_AXIS_VIDEO_RGB888_tuser(ps_rgb888_user),
    .S_AXIS_VIDEO_RGB888_tvalid(ps_rgb888_valid),
    .TOUCH_GPIO_tri_i(ps_touch_gpio_i), .TOUCH_GPIO_tri_o(ps_touch_gpio_o),
    .TOUCH_GPIO_tri_t(ps_touch_gpio_t),
    .TOUCH_IIC_scl_i(ps_touch_i2c_scl_i), .TOUCH_IIC_scl_o(ps_touch_i2c_scl_o),
    .TOUCH_IIC_scl_t(ps_touch_i2c_scl_t), .TOUCH_IIC_sda_i(ps_touch_i2c_sda_i),
    .TOUCH_IIC_sda_o(ps_touch_i2c_sda_o), .TOUCH_IIC_sda_t(ps_touch_i2c_sda_t),
    .pl_fault_irq(adc_timeout), .pl_harmonic_irq(harmonic_irq), .pl_snapshot_irq(snapshot_irq)
);

// PS触摸边界把I2C EMIO和GPIO EMIO连接到面板及物理按键。
pqm_touch_iobuf u_pqm_touch_iobuf (
    .ps_i2c_scl_o(ps_touch_i2c_scl_o), .ps_i2c_scl_t(ps_touch_i2c_scl_t),
    .ps_i2c_scl_i(ps_touch_i2c_scl_i), .ps_i2c_sda_o(ps_touch_i2c_sda_o),
    .ps_i2c_sda_t(ps_touch_i2c_sda_t), .ps_i2c_sda_i(ps_touch_i2c_sda_i),
    .ps_gpio_o(ps_touch_gpio_o), .ps_gpio_i(ps_touch_gpio_i),
    .touch_scl(touch_scl), .touch_sda(touch_sda),
    .touch_int(touch_int), .touch_rst_n(touch_rst_n), .key0(key0)
);

// 板级PL UART已停用，发送引脚保持8N1空闲高电平。
assign uart_txd = 1'b1;

// PS视频通路持续驱动LCD RGB888数据总线。
assign lcd_rgb = ps_lcd_data;

// PS Video Out的active_video作为LCD数据有效。
assign lcd_de = ps_lcd_active_video;

// PS VTC产生LCD行同步。
assign lcd_hs = ps_lcd_hsync;

// PS VTC产生LCD场同步。
assign lcd_vs = ps_lcd_vsync;

// 背光保持开启，后续可由PS GPIO或PWM接管亮度。
assign lcd_bl = 1'b1;

// PS像素时钟驱动LCD采样时钟。
assign lcd_clk = ps_pixel_clk;

// PS像素域复位直接控制LCD复位。
assign lcd_rst_n = ps_pixel_resetn[0];

endmodule
