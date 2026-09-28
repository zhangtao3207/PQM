`timescale 1ns / 1ps
/*
 * 模块名称：pqm2_top
 * 功能说明：PQM2 SoC 系统顶层。把官方视频段（BD `pqm_ps`，含 PS7/VDMA/v_tc/
 *   v_axi4s_vid_out/共享 BRAM/axi_bram_ctrl/触摸 EMIO 等）与 PQM2 自研的 PL 测量段
 *   （`pqm_pl_top`）连成一个完整系统。
 *
 * 时钟与复位：
 *   sys_clk（板载 U18 50 MHz 晶振）→ clk_wiz_0 → clk_out1 = 50 MHz，作为整条 PL
 *   测量链与共享内存 BRAM 端口 B 的工作时钟（`pl_clk`）。
 *   PS 侧 FCLK_CLK0 = 100 MHz 由 BD 内部产生，只用于 AXI 域，引出为 `ps_axi_clk`
 *   但本顶层不消费（仅留观察）。
 *   `pl_resetn = sys_rst_n & locked`，与旧工程 `pqm_pl_core` 的
 *   `assign rst_n = sys_rst_n & locked;` 完全一致（MMCM 未锁定期间保持复位）。
 *
 * 视频段接法（与旧工程 main.v 一致）：
 *   LCD_VIDEO_* 并行视频输出直接驱动 LCD 引脚；VDMA 的 RGB565 流经
 *   `pqm_axis_rgb565_to_rgb888` 还原成 RGB888 后回送给 BD 的
 *   `S_AXIS_VIDEO_RGB888` 输入。
 *
 * 输入端口：见下方端口表。
 * 输出端口：见下方端口表。
 * 双向端口：lcd 数据线在本设计里只输出，故声明为 output；触摸 I2C 为真双向。
 */

module pqm2_top (
    // ---------------- 系统 ----------------
    input  wire        sys_clk,          // 板载 50 MHz 晶振 U18
    input  wire        sys_rst_n,        // 板级低有效复位 N16
    input  wire        key0,             // 物理按键 L14（送 PS GPIO EMIO）
    input  wire        uart_rxd,         // 板级串口输入，PL 不处理
    output wire        uart_txd,         // 板级串口输出，固定空闲高
    output wire        led,              // 告警指示 H15
    output wire        buzzer,           // 告警蜂鸣器 M14

    // ---------------- 触摸面板 ----------------
    inout  wire        touch_scl,        // 触摸 I2C 时钟
    inout  wire        touch_sda,        // 触摸 I2C 数据
    input  wire        touch_int,        // 触摸中断输入
    output wire        touch_rst_n,      // 触摸芯片低有效复位（PS GPIO0 驱动）

    // ---------------- LCD ----------------
    output wire [23:0] lcd_rgb,          // PS 视频通路输出的 RGB888
    output wire        lcd_hs,           // 行同步
    output wire        lcd_vs,           // 场同步
    output wire        lcd_de,           // 数据有效
    output wire        lcd_bl,           // 背光
    output wire        lcd_clk,          // 像素时钟
    output wire        lcd_rst_n,        // LCD 低有效复位

    // ---------------- AD7606 并行 ADC ----------------
    output wire        OS0,              // 过采样配置位（本设计固定 0）
    output wire        OS1,
    output wire        OS2,
    output wire        Convst,           // 转换启动
    output wire        RD,               // 读选通
    output wire        RESET,            // ADC 硬件复位
    input  wire        Busy,             // 转换忙
    output wire        cs,               // 片选
    output wire        Range,            // 输入范围选择（本设计固定 1）
    input  wire        Frstdata,         // 首数据标志
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

    // ---------------- PS DDR3 ----------------
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

    // ---------------- PS 固定 IO ----------------
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

    // ==================================================================
    // 1. 测量链时钟：板载 50 MHz 晶振 -> clk_wiz_0 -> 50 MHz
    //    clk_out2（25 MHz）/clk_out3（25 MHz 相位 120°）本设计不用，留空。
    // ==================================================================
    wire pl_clk;      // 50 MHz 测量链时钟
    wire locked;      // MMCM 锁定指示

    clk_wiz_0 u_clk_wiz_0 (
        .clk_out1 (pl_clk),
        .clk_out2 (),
        .clk_out3 (),
        .locked   (locked),
        .clk_in1  (sys_clk)
    );

    // MMCM 锁定前保持复位（与旧工程 pqm_pl_core 的写法一致）。
    wire pl_resetn = sys_rst_n & locked;

    // ==================================================================
    // 2. BD（官方视频段 + PS）互联信号
    // ==================================================================
    // 视频：VDMA RGB565 -> RGB888 -> v_axi4s_vid_out
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

    // 像素域
    wire        ps_pixel_clk;
    wire [0:0]  ps_pixel_resetn;

    // LCD 并行视频输出
    wire        ps_lcd_active_video;
    wire [23:0] ps_lcd_data;
    wire        ps_lcd_field;
    wire        ps_lcd_hblank;
    wire        ps_lcd_hsync;
    wire        ps_lcd_vblank;
    wire        ps_lcd_vsync;

    // AXI 域（FCLK_CLK0 = 100 MHz）
    wire        ps_axi_clk;
    wire [0:0]  ps_axi_resetn;

    // 触摸 EMIO
    wire [63:0] ps_touch_gpio_i;
    wire [63:0] ps_touch_gpio_o;
    wire [63:0] ps_touch_gpio_t;
    wire        ps_touch_i2c_scl_i;
    wire        ps_touch_i2c_scl_o;
    wire        ps_touch_i2c_scl_t;
    wire        ps_touch_i2c_sda_i;
    wire        ps_touch_i2c_sda_o;
    wire        ps_touch_i2c_sda_t;

    // 原始样本 AXI4-Stream（BD 侧 CDC -> DMA）：本设计未接入源，固定无效。
    wire        sample_axis_ready;

    // 共享内存桥（BRAM 端口 B）
    wire [13:0] bram_addr;      // PL 侧字地址
    wire [31:0] bram_wrdata;
    wire [31:0] bram_rddata;
    wire [3:0]  bram_we;
    wire        bram_en;

    // PL->PS 中断
    wire        pl_fault_irq;
    wire        pl_harmonic_irq;
    wire        pl_snapshot_irq;

    // PS 视频段：RGB565 扩展为 RGB888 后回送 BD 的视频输入。
    pqm_axis_rgb565_to_rgb888 u_rgb565_to_rgb888 (
        .clk            (ps_pixel_clk),
        .rst_n          (ps_pixel_resetn[0]),
        .s_axis_tdata   (ps_rgb565_data),
        .s_axis_tvalid  (ps_rgb565_valid),
        .s_axis_tready  (ps_rgb565_ready),
        .s_axis_tuser   (ps_rgb565_user),
        .s_axis_tlast   (ps_rgb565_last),
        .m_axis_tdata   (ps_rgb888_data),
        .m_axis_tvalid  (ps_rgb888_valid),
        .m_axis_tready  (ps_rgb888_ready),
        .m_axis_tuser   (ps_rgb888_user),
        .m_axis_tlast   (ps_rgb888_last)
    );

    // 直接实例化 BD 模块本体（而非 _wrapper），保留 EMIO 的 I/O/T 三态信号，
    // 避免为未使用的 GPIO 位插入 IOBUF——旧工程 main.v 采用同一做法。
    pqm_ps u_pqm_ps (
        .DDR_addr                    (DDR_addr),
        .DDR_ba                      (DDR_ba),
        .DDR_cas_n                   (DDR_cas_n),
        .DDR_ck_n                    (DDR_ck_n),
        .DDR_ck_p                    (DDR_ck_p),
        .DDR_cke                     (DDR_cke),
        .DDR_cs_n                    (DDR_cs_n),
        .DDR_dm                      (DDR_dm),
        .DDR_dq                      (DDR_dq),
        .DDR_dqs_n                   (DDR_dqs_n),
        .DDR_dqs_p                   (DDR_dqs_p),
        .DDR_odt                     (DDR_odt),
        .DDR_ras_n                   (DDR_ras_n),
        .DDR_reset_n                 (DDR_reset_n),
        .DDR_we_n                    (DDR_we_n),
        .FIXED_IO_ddr_vrn            (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp            (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio                (FIXED_IO_mio),
        .FIXED_IO_ps_clk             (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb            (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb           (FIXED_IO_ps_srstb),
        .LCD_VIDEO_active_video      (ps_lcd_active_video),
        .LCD_VIDEO_data              (ps_lcd_data),
        .LCD_VIDEO_field             (ps_lcd_field),
        .LCD_VIDEO_hblank            (ps_lcd_hblank),
        .LCD_VIDEO_hsync             (ps_lcd_hsync),
        .LCD_VIDEO_vblank            (ps_lcd_vblank),
        .LCD_VIDEO_vsync             (ps_lcd_vsync),
        .M_AXIS_VIDEO_RGB565_tdata   (ps_rgb565_data),
        .M_AXIS_VIDEO_RGB565_tkeep   (ps_rgb565_keep),
        .M_AXIS_VIDEO_RGB565_tlast   (ps_rgb565_last),
        .M_AXIS_VIDEO_RGB565_tready  (ps_rgb565_ready),
        .M_AXIS_VIDEO_RGB565_tuser   (ps_rgb565_user),
        .M_AXIS_VIDEO_RGB565_tvalid  (ps_rgb565_valid),
        .PIXEL_ARESETN               (ps_pixel_resetn),
        .PIXEL_CLK                   (ps_pixel_clk),
        .PL_AXI_ARESETN              (ps_axi_resetn),
        .PL_AXI_CLK                  (ps_axi_clk),
        // BD 侧 PL_SHARED_BRAM_addr 是**字节地址**，RTL 的 bram_addr 是字地址，
        // 必须左移 2 位补齐；否则写入会被 BRAM 按字节解释（等效 >>2）。
        .PL_SHARED_BRAM_addr         ({16'd0, bram_addr, 2'b00}),
        .PL_SHARED_BRAM_clk          (pl_clk),
        .PL_SHARED_BRAM_din          (bram_wrdata),
        .PL_SHARED_BRAM_dout         (bram_rddata),
        .PL_SHARED_BRAM_en           (bram_en),
        .PL_SHARED_BRAM_rst          (~pl_resetn),
        .PL_SHARED_BRAM_we           (bram_we),
        .SAMPLE_AXIS_ARESETN         (pl_resetn),
        .SAMPLE_AXIS_CLK             (pl_clk),
        // 本设计不产生原始样本流：S_AXIS_SAMPLES 固定为无效。
        .S_AXIS_SAMPLES_tdata        (64'd0),
        .S_AXIS_SAMPLES_tkeep        (8'h00),
        .S_AXIS_SAMPLES_tlast        (1'b0),
        .S_AXIS_SAMPLES_tready       (sample_axis_ready),
        .S_AXIS_SAMPLES_tvalid       (1'b0),
        .S_AXIS_VIDEO_RGB888_tdata   (ps_rgb888_data),
        .S_AXIS_VIDEO_RGB888_tlast   (ps_rgb888_last),
        .S_AXIS_VIDEO_RGB888_tready  (ps_rgb888_ready),
        .S_AXIS_VIDEO_RGB888_tuser   (ps_rgb888_user),
        .S_AXIS_VIDEO_RGB888_tvalid  (ps_rgb888_valid),
        .TOUCH_GPIO_tri_i            (ps_touch_gpio_i),
        .TOUCH_GPIO_tri_o            (ps_touch_gpio_o),
        .TOUCH_GPIO_tri_t            (ps_touch_gpio_t),
        .TOUCH_IIC_scl_i             (ps_touch_i2c_scl_i),
        .TOUCH_IIC_scl_o             (ps_touch_i2c_scl_o),
        .TOUCH_IIC_scl_t             (ps_touch_i2c_scl_t),
        .TOUCH_IIC_sda_i             (ps_touch_i2c_sda_i),
        .TOUCH_IIC_sda_o             (ps_touch_i2c_sda_o),
        .TOUCH_IIC_sda_t             (ps_touch_i2c_sda_t),
        .pl_fault_irq                (pl_fault_irq),
        .pl_harmonic_irq             (pl_harmonic_irq),
        .pl_snapshot_irq             (pl_snapshot_irq)
    );

    // PS 的 I2C/GPIO EMIO 落到面板与按键。
    pqm_touch_iobuf u_pqm_touch_iobuf (
        .ps_i2c_scl_o (ps_touch_i2c_scl_o),
        .ps_i2c_scl_t (ps_touch_i2c_scl_t),
        .ps_i2c_scl_i (ps_touch_i2c_scl_i),
        .ps_i2c_sda_o (ps_touch_i2c_sda_o),
        .ps_i2c_sda_t (ps_touch_i2c_sda_t),
        .ps_i2c_sda_i (ps_touch_i2c_sda_i),
        .ps_gpio_o    (ps_touch_gpio_o),
        .ps_gpio_i    (ps_touch_gpio_i),
        .touch_scl    (touch_scl),
        .touch_sda    (touch_sda),
        .touch_int    (touch_int),
        .touch_rst_n  (touch_rst_n),
        .key0         (key0)
    );

    // ==================================================================
    // 3. PL 测量段
    //    生产参数：MEASUREMENT_INTERVAL_CYCLES = 16_000_000，
    //              MEASURE_FRAME_SAMPLES = 6144，FORCE_ZERO_CENTER = 0。
    // ==================================================================
    (* keep = "true" *) wire [511:0] pl_snapshot_words;          // 当前标量快照（观察点）
    (* keep = "true" *) wire         pl_snapshot_commit_toggle;  // 快照提交（电平翻转）
    (* keep = "true" *) wire         pl_alarm_active;            // 保护告警
    (* keep = "true" *) wire         pl_adc_tick_pending;        // 采样节拍被驱动忙挡住（丢样本）
    (* keep = "true" *) wire         pl_low_range_active;        // 命令确认后的低量程状态

    pqm_pl_top #(
        .MEASUREMENT_INTERVAL_CYCLES (16_000_000),
        .MEASURE_FRAME_SAMPLES       (6144),
        .FORCE_ZERO_CENTER           (0)
    ) u_pqm_pl_top (
        .clk                         (pl_clk),
        .rst_n                       (pl_resetn),
        .ad_busy                     (Busy),
        .ad_frstdata                 (Frstdata),
        .ad_data                     ({DB15, DB14, DB13, DB12, DB11, DB10, DB9, DB8,
                                       DB7,  DB6,  DB5,  DB4,  DB3,  DB2,  DB1, DB0}),
        .ad_reset                    (RESET),
        .ad_convst                   (Convst),
        .ad_cs_n                     (cs),
        .ad_rd_n                     (RD),
        // 注意：pqm_pl_top 把 command_response_valid 声明成了 input，但内部又把它接到
        // pqm_range_command_controller 的 response_valid（output reg）上，属于多驱动。
        // 仿真里 TB 用 1'b0 掩盖了它，综合会报 multi-driven net。
        // 这里**不连接**该端口，让内部控制器单独驱动它，行为与设计意图一致。
        // .command_response_valid   (),
        .bram_rddata                 (bram_rddata),
        .bram_addr                   (bram_addr),
        .bram_wrdata                 (bram_wrdata),
        .bram_we                     (bram_we),
        .bram_en                     (bram_en),
        .ps_snapshot_words           (pl_snapshot_words),
        .ps_snapshot_commit_toggle   (pl_snapshot_commit_toggle),
        .alarm_active                (pl_alarm_active),
        .adc_tick_pending            (pl_adc_tick_pending),
        .low_range_active            (pl_low_range_active)
    );

    // ==================================================================
    // 4. 中断映射与板级指示
    //    pl_fault_irq    <- 保护告警（alarm_active）：语义即"故障"
    //    pl_snapshot_irq <- 快照提交事件：commit 是"每帧翻转一次的电平"，
    //                       这里做边沿检测还原成单拍脉冲（旧工程同样把
    //                       sequence 变化整形成脉冲送给 PS）。
    //    pl_harmonic_irq <- 1'b0：pqm_pl_top 没有导出谐波帧完成事件，
    //                       不拿别的信号凑语义；该中断线在本系统里恒不触发。
    // ==================================================================
    reg snap_toggle_d;

    always @(posedge pl_clk or negedge pl_resetn) begin
        if (!pl_resetn) begin
            snap_toggle_d <= 1'b0;
        end else begin
            snap_toggle_d <= pl_snapshot_commit_toggle;
        end
    end

    assign pl_fault_irq    = pl_alarm_active;
    assign pl_snapshot_irq = pl_snapshot_commit_toggle ^ snap_toggle_d;
    assign pl_harmonic_irq = 1'b0;

    // 告警直接上板：LED 与蜂鸣器同步指示。
    assign led    = pl_alarm_active;
    assign buzzer = pl_alarm_active;

    // ==================================================================
    // 5. AD7606 静态配置位（与旧工程 pqm_pl_core 一致）
    //    OS2:OS1:OS0 = 000（不做过采样），Range = 1（±10 V 档）。
    //    RESET/Convst/cs/RD 由 pqm_pl_top 内部的 AD7606 驱动产生。
    // ==================================================================
    assign OS0   = 1'b0;
    assign OS1   = 1'b0;
    assign OS2   = 1'b0;
    assign Range = 1'b1;

    // ==================================================================
    // 6. 视频与串口引脚的最终驱动（与旧工程 main.v 一致）
    // ==================================================================
    assign lcd_rgb   = ps_lcd_data;
    assign lcd_de    = ps_lcd_active_video;
    assign lcd_hs    = ps_lcd_hsync;
    assign lcd_vs    = ps_lcd_vsync;
    assign lcd_bl    = 1'b1;
    assign lcd_clk   = ps_pixel_clk;
    assign lcd_rst_n = ps_pixel_resetn[0];

    // 板级 PL UART 已停用，发送引脚保持 8N1 空闲高电平。
    assign uart_txd = 1'b1;

    // ==================================================================
    // 7. 未使用的合法信号汇入一个 keep 网络，避免综合产生大量
    //    "assigned but unused" 告警（不改变功能）。
    // ==================================================================
    (* keep = "true" *) wire [7:0] _unused = {
        1'b0,
        uart_rxd,
        pl_adc_tick_pending,
        pl_low_range_active,
        ps_lcd_field,
        ps_lcd_hblank,
        ps_lcd_vblank,
        pl_snapshot_commit_toggle
    };

endmodule
