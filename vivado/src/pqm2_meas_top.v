`timescale 1ns / 1ps
/*
 * 模块名称：pqm2_meas_top
 * 功能说明：PQM2 测量版系统顶层 = 官方基线视频/PS 段（BD `system`）
 *           + PS/PL 共享内存（BD 内 axi_bram_ctrl_0 + blk_mem_gen_shared）
 *           + PQM2 自研 PL 测量链（`pqm_pl_top`）。
 *
 * 与官方基线的关系：
 *   官方基线 BD 的显示通路（PS7 -> VDMA -> v_axi4s_vid_out -> rgb2lcd）原样保留，
 *   本顶层只做三件事：给 BD 提供时钟/复位/引脚，把 AD7606 引脚接给测量链，
 *   把测量链的 BRAM 端口 B 接到 BD 的 PL_SHARED_BRAM 上。
 *
 * 时钟与复位：
 *   sys_clk（板载 U18 50 MHz 晶振）-> clk_wiz_0 -> clk_out1 = 50 MHz（pl_clk），
 *   作为整条 PL 测量链与共享内存 BRAM 端口 B 的工作时钟。
 *   显示/AXI 域仍由 BD 内部 PS7 的 FCLK_CLK0 = 100 MHz 提供，互不相干。
 *   pl_resetn = sys_rst_n & locked（与旧工程 pqm_pl_core 的写法一致）。
 *
 * 共享内存地址换算（关键）：
 *   BD 侧 PL_SHARED_BRAM_addr 是**字节地址**（32 位），RTL 的 bram_addr 是
 *   14 位**字地址**，必须 {16'd0, bram_addr, 2'b00} 左移 2 位再送过去，
 *   否则写入会被 BRAM 按字节解释（等效把地址右移 2 位）。
 *   这一接法与只读参考工程 PQM/FPGA/rtl/main.v 第 343-347 行逐字一致。
 *
 * AD7606 静态配置位：OS2:OS1:OS0 = 000（不做过采样），Range = 1（±10 V 档）；
 *   与旧工程 pqm_pl_core 的 assign 一致。RESET/Convst/cs/RD 由测量链内部的
 *   AD7606 驱动产生。
 *
 * lcd_rgb / GPIO_EMIO 是 BD 的三态接口，本顶层按官方生成的 wrapper 同样方式
 *   插入 IOBUF（不额外引 IOBUF 会给未使用的位带来多余缓冲）。
 */
module pqm2_meas_top (
    // ---------------- 系统时钟与复位 ----------------
    input  wire        sys_clk,          // 板载 50 MHz 晶振 U18
    input  wire        sys_rst_n,        // 板级低有效复位 N16

    // ---------------- AD7606 并行 ADC ----------------
    output wire        OS0,              // 过采样配置位 0（固定 0）
    output wire        OS1,              // 过采样配置位 1（固定 0）
    output wire        OS2,              // 过采样配置位 2（固定 0）
    output wire        Convst,           // 转换启动
    output wire        RD,               // 读选通
    output wire        RESET,            // ADC 硬件复位
    input  wire        Busy,             // 转换忙
    output wire        cs,               // 片选
    output wire        Range,            // 输入范围选择（固定 1 = ±10 V）
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

    // ---------------- LCD（官方基线视频通路直接驱动） ----------------
    inout  wire [23:0] lcd_rgb_tri_io,
    output wire        lcd_hs,
    output wire        lcd_vs,
    output wire        lcd_de,
    output wire        lcd_bl,
    output wire        lcd_clk,
    output wire        lcd_rst,

    // ---------------- 触摸用 PS EMIO GPIO ----------------
    inout  wire [3:0]  GPIO_EMIO_tri_io,

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

    // MMCM 锁定前保持复位。
    wire pl_resetn = sys_rst_n & locked;

    // 共享内存 BRAM 的复位：IP 配置为 Reset_Type = SYNC，但 pl_resetn 来自按键、是异步的。
    // 异步复位直接驱动同步复位单元，释放边沿可能与 pl_clk 任意对齐，
    // 导致各触发器在不同时钟沿退出复位。故先过一级"异步置位、同步释放"的同步器，
    // 再取反送给 BD 的 PL_SHARED_BRAM_rst（该端口高有效）。
    // PL_SHARED_BRAM_clk 就是 pl_clk，与同步器同域。
    wire bram_reset_n;
    reset_sync_n u_bram_reset_sync (
        .clk           (pl_clk),
        .async_reset_n (pl_resetn),
        .reset_n_out   (bram_reset_n)
    );

    // ==================================================================
    // 2. BD 三态接口的 IOBUF（与官方生成的 system_wrapper 完全等价）
    // ==================================================================
    wire [23:0] lcd_rgb_tri_i, lcd_rgb_tri_o, lcd_rgb_tri_t;
    wire [3:0]  gpio_emio_tri_i, gpio_emio_tri_o, gpio_emio_tri_t;

    genvar gi;
    generate
        for (gi = 0; gi < 24; gi = gi + 1) begin : g_lcd_rgb_iobuf
            IOBUF lcd_rgb_iobuf (
                .I  (lcd_rgb_tri_o[gi]),
                .IO (lcd_rgb_tri_io[gi]),
                .O  (lcd_rgb_tri_i[gi]),
                .T  (lcd_rgb_tri_t[gi])
            );
        end
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_gpio_emio_iobuf
            IOBUF gpio_emio_iobuf (
                .I  (gpio_emio_tri_o[gi]),
                .IO (GPIO_EMIO_tri_io[gi]),
                .O  (gpio_emio_tri_i[gi]),
                .T  (gpio_emio_tri_t[gi])
            );
        end
    endgenerate

    // ==================================================================
    // 3. 共享内存桥（BD 里 blk_mem_gen_shared 的端口 B）
    // ==================================================================
    wire [13:0] bram_addr;      // PL 侧字地址
    wire [31:0] bram_wrdata;
    wire [31:0] bram_rddata;
    wire [3:0]  bram_we;
    wire        bram_en;

    // ==================================================================
    // 4. BD 本体（官方视频段 + PS7 + 共享内存）
    //    直接实例化 BD 模块，保留 EMIO 的 I/O/T 三态信号，自己插 IOBUF。
    // ==================================================================
    system system_i (
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
        .GPIO_EMIO_tri_i             (gpio_emio_tri_i),
        .GPIO_EMIO_tri_o             (gpio_emio_tri_o),
        .GPIO_EMIO_tri_t             (gpio_emio_tri_t),
        .lcd_bl                      (lcd_bl),
        .lcd_clk                     (lcd_clk),
        .lcd_de                      (lcd_de),
        .lcd_hs                      (lcd_hs),
        .lcd_rgb_tri_i               (lcd_rgb_tri_i),
        .lcd_rgb_tri_o               (lcd_rgb_tri_o),
        .lcd_rgb_tri_t               (lcd_rgb_tri_t),
        .lcd_rst                     (lcd_rst),
        .lcd_vs                      (lcd_vs),
        // 共享内存端口 B：BD 侧是字节地址，必须把字地址左移 2 位。
        .PL_SHARED_BRAM_addr         ({16'd0, bram_addr, 2'b00}),
        .PL_SHARED_BRAM_clk          (pl_clk),
        .PL_SHARED_BRAM_din          (bram_wrdata),
        .PL_SHARED_BRAM_dout         (bram_rddata),
        .PL_SHARED_BRAM_en           (bram_en),
        .PL_SHARED_BRAM_rst          (~bram_reset_n),
        .PL_SHARED_BRAM_we           (bram_we)
    );

    // ==================================================================
    // 5. PL 测量链
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
        // command_response_valid 曾是 pqm_pl_top 的端口（与内部 pqm_range_command_controller
        // 的 response_valid 多驱动）。该缺陷已在 PL 侧修掉：端口已从 pqm_pl_top 移除，
        // 由控制器内部单独驱动，这里无需再有任何连接或规避。
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
    // 6. 未用信号汇入 keep 网络，避免大量 "assigned but unused" 告警
    // ==================================================================
    (* keep = "true" *) wire [3:0] _unused = {
        pl_adc_tick_pending,
        pl_low_range_active,
        pl_alarm_active,
        pl_snapshot_commit_toggle
    };

    // ==================================================================
    // 7. AD7606 静态配置位（与旧工程 pqm_pl_core 一致）
    // ==================================================================
    assign OS0   = 1'b0;
    assign OS1   = 1'b0;
    assign OS2   = 1'b0;
    assign Range = 1'b1;

endmodule
