`timescale 1ns / 1ps

/*
 * 模块: tb_AD7606_Parallel_DRIVER
 * 功能:
 *   AD7606 并行采样通路的单元测试平台。
 *
 *   平台自带一个 AD7606 芯片行为模型，只通过引脚与 DUT 交互：
 *     - 看到 CONVST 上升沿后拉高 BUSY，保持一个转换时间再拉低；
 *     - 转换完成后把 FRSTDATA 拉高，并在第一次 RD 上升沿把它拉低
 *       （对应数据手册“FRSTDATA 在第一次读的上升沿归低”）；
 *     - 每来一个 RD 上升沿切换到下一个通道的数据放到 DB[15:0] 上。
 *
 *   三个场景：
 *     1) 正常一帧：8 个通道数据与整帧拼接正确，无超时；
 *     2) FRSTDATA 缺失：首个读窗口末尾看不到 FRSTDATA，应报超时；
 *     3) BUSY 始终不拉高：应在 BUSY 超时窗口后报超时。
 */

module tb_AD7606_Parallel_DRIVER;

    localparam integer CLK_PERIOD  = 10;    // 100 MHz，与设计中 FCLK0 一致
    localparam integer CONV_CYCLES = 400;   // 模拟 4 us 转换时间
    localparam integer WATCHDOG_NS = 20000000; // 20 ms 兜底

    // 芯片模型给 8 个通道准备的数据；最后两个用位宽边界，检查符号位不被吞掉
    reg [15:0] ch_pattern [0:7];

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg soft_reset = 1'b0;

    // 两个故障注入开关
    reg busy_never_high  = 1'b0;
    reg frstdata_missing = 1'b0;

    wire        ad_reset;
    wire        ad_convst;
    wire        ad_cs_n;
    wire        ad_rd_n;
    wire [15:0] ch1_data, ch2_data, ch3_data, ch4_data;
    wire [15:0] ch5_data, ch6_data, ch7_data, ch8_data;
    wire [127:0] data_frame;
    wire        data_valid;
    wire        sample_active;
    wire        timeout;
    wire [3:0]  ad_channal;
    wire [2:0]  ad_state;

    reg         ad_busy;
    reg         ad_frstdata;
    reg  [15:0] ad_data;

    integer errors = 0;
    integer i;

    // 一帧内出现过的最大通道号，用来确认通道确实按 1~8 顺序走
    reg [3:0] max_channel;

    always #(CLK_PERIOD / 2) clk = ~clk;

    AD7606_Parallel_DRIVER dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .soft_reset(soft_reset),
        .ad_busy(ad_busy),
        .ad_frstdata(ad_frstdata),
        .ad_data(ad_data),
        .ad_reset(ad_reset),
        .ad_convst(ad_convst),
        .ad_cs_n(ad_cs_n),
        .ad_rd_n(ad_rd_n),
        .ch1_data(ch1_data),
        .ch2_data(ch2_data),
        .ch3_data(ch3_data),
        .ch4_data(ch4_data),
        .ch5_data(ch5_data),
        .ch6_data(ch6_data),
        .ch7_data(ch7_data),
        .ch8_data(ch8_data),
        .data_frame(data_frame),
        .data_valid(data_valid),
        .sample_active(sample_active),
        .timeout(timeout),
        .ad_channal(ad_channal),
        .ad_state(ad_state)
    );

    // ------------------------------------------------------------------
    // AD7606 芯片行为模型
    // ------------------------------------------------------------------
    localparam [1:0] M_IDLE = 2'd0, M_CONV = 2'd1, M_READY = 2'd2;

    reg [1:0]  mdl_state;
    reg [2:0]  mdl_ch;
    reg [31:0] mdl_cnt;
    reg        ad_convst_d;
    reg        ad_rd_n_d;

    wire convst_rise = ad_convst & ~ad_convst_d;
    wire rd_rise     = ad_rd_n & ~ad_rd_n_d;

    // 数据总线跟着当前通道走；控制器在 RD 低电平窗口末尾采样它
    always @(*) ad_data = ch_pattern[mdl_ch];

    initial begin
        mdl_state   = M_IDLE;
        mdl_ch      = 3'd0;
        mdl_cnt     = 0;
        ad_busy     = 1'b0;
        ad_frstdata = 1'b0;
        ad_convst_d = 1'b1;
        ad_rd_n_d   = 1'b1;
        max_channel = 4'd0;
    end

    always @(posedge clk) begin
        ad_convst_d <= ad_convst;
        ad_rd_n_d   <= ad_rd_n;

        if (start) max_channel <= 4'd0;
        else if (ad_channal > max_channel) max_channel <= ad_channal;

        if (!rst_n || ad_reset) begin
            mdl_state   <= M_IDLE;
            mdl_ch      <= 3'd0;
            mdl_cnt     <= 0;
            ad_busy     <= 1'b0;
            ad_frstdata <= 1'b0;
        end else if (convst_rise && !busy_never_high) begin
            // 一次新的转换开始：唯一入口，故障注入在这里统一生效。
            // 之前把这段写在 M_IDLE 和 M_READY 两处，busy_never_high 只在 M_IDLE 判了，
            // 结果上一个场景收尾停在 M_READY 时，故障注入就失效了。
            ad_frstdata <= 1'b0;
            mdl_ch      <= 3'd0;
            mdl_cnt     <= CONV_CYCLES;
            ad_busy     <= 1'b1;
            mdl_state   <= M_CONV;
        end else begin
            case (mdl_state)
                M_IDLE: begin
                    ad_busy     <= 1'b0;
                    ad_frstdata <= 1'b0;
                    mdl_ch      <= 3'd0;
                end

                M_CONV: begin
                    if (mdl_cnt == 0) begin
                        ad_busy     <= 1'b0;
                        ad_frstdata <= frstdata_missing ? 1'b0 : 1'b1;
                        mdl_ch      <= 3'd0;
                        mdl_state   <= M_READY;
                    end else begin
                        mdl_cnt <= mdl_cnt - 1'b1;
                    end
                end

                M_READY: begin
                    ad_busy <= 1'b0;
                    if (rd_rise) begin
                        if (mdl_ch == 3'd0) ad_frstdata <= 1'b0;
                        if (mdl_ch != 3'd7) mdl_ch <= mdl_ch + 1'b1;
                    end
                end

                default: mdl_state <= M_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // 测试流程
    // ------------------------------------------------------------------

    // 调试跟踪：打印引脚与状态的每次变化，定位用；跑通后可以关掉（dbg_on）
    reg [2:0] dbg_state_d;
    reg dbg_convst_d, dbg_cs_d, dbg_rd_d, dbg_busy_d, dbg_frst_d;
    reg [3:0] dbg_ch_d;
    reg dbg_on = 1'b1;

    always @(posedge clk) begin
        dbg_state_d  <= ad_state;
        dbg_convst_d <= ad_convst;
        dbg_cs_d     <= ad_cs_n;
        dbg_rd_d     <= ad_rd_n;
        dbg_busy_d   <= ad_busy;
        dbg_frst_d   <= ad_frstdata;
        dbg_ch_d     <= ad_channal;
        if (dbg_on && (ad_state !== dbg_state_d || ad_convst !== dbg_convst_d ||
                       ad_cs_n !== dbg_cs_d || ad_rd_n !== dbg_rd_d ||
                       ad_busy !== dbg_busy_d || ad_frstdata !== dbg_frst_d ||
                       ad_channal !== dbg_ch_d)) begin
            $display("t=%0t st=%0d convst=%b cs=%b rd=%b busy=%b frst=%b ch=%0d di=%h",
                     $time, ad_state, ad_convst, ad_cs_n, ad_rd_n,
                     ad_busy, ad_frstdata, ad_channal, ad_data);
        end
    end

    initial begin
        #200000;
        dbg_on = 1'b0;
    end
    task issue_start;
        begin
            // 在时钟低电平期间改变激励，避免与 posedge 采样撞在同一个时间步里
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    // 轮询等待某个条件成立；返回等待的时钟数，超时返回 -1
    task wait_data_valid;
        input integer max_cycles;
        output integer waited;
        reg seen;
        begin
            seen = 1'b0;
            waited = 0;
            for (i = 0; i < max_cycles && !seen; i = i + 1) begin
                @(posedge clk);
                waited = waited + 1;
                if (data_valid) seen = 1'b1;
            end
            if (!seen) waited = -1;
        end
    endtask

    task wait_timeout;
        input integer max_cycles;
        output integer waited;
        reg seen;
        begin
            seen = 1'b0;
            waited = 0;
            for (i = 0; i < max_cycles && !seen; i = i + 1) begin
                @(posedge clk);
                waited = waited + 1;
                if (timeout) seen = 1'b1;
            end
            if (!seen) waited = -1;
        end
    endtask

    integer waited;
    reg seen_valid;

    initial begin
        ch_pattern[0] = 16'h1111;
        ch_pattern[1] = 16'h2222;
        ch_pattern[2] = 16'h3333;
        ch_pattern[3] = 16'h4444;
        ch_pattern[4] = 16'h5555;
        ch_pattern[5] = 16'h6666;
        ch_pattern[6] = 16'h7FFF;   // 正满量程
        ch_pattern[7] = 16'h8000;   // 负满量程

        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // 等控制器把 RESET_HIGH_CYCLES 走完、进入空闲
        for (i = 0; i < 2000; i = i + 1) begin
            @(posedge clk);
            if (ad_state == 3'd1) i = 2000;
        end
        if (ad_state !== 3'd1) begin
            $display("FAIL: 复位后没有回到空闲状态，ad_state=%0d", ad_state);
            errors = errors + 1;
        end

        // ---------------- 场景 1：正常一帧 ----------------
        issue_start;
        wait_data_valid(20000, waited);
        seen_valid = (waited >= 0);

        if (!seen_valid) begin
            $display("FAIL: 正常帧没有产生 data_valid");
            errors = errors + 1;
        end else begin
            if (timeout !== 1'b0) begin
                $display("FAIL: 正常帧出现了 timeout");
                errors = errors + 1;
            end
            if (ch1_data !== 16'h1111) begin $display("FAIL: ch1_data=%h 期望 1111", ch1_data); errors = errors + 1; end
            if (ch2_data !== 16'h2222) begin $display("FAIL: ch2_data=%h 期望 2222", ch2_data); errors = errors + 1; end
            if (ch3_data !== 16'h3333) begin $display("FAIL: ch3_data=%h 期望 3333", ch3_data); errors = errors + 1; end
            if (ch4_data !== 16'h4444) begin $display("FAIL: ch4_data=%h 期望 4444", ch4_data); errors = errors + 1; end
            if (ch5_data !== 16'h5555) begin $display("FAIL: ch5_data=%h 期望 5555", ch5_data); errors = errors + 1; end
            if (ch6_data !== 16'h6666) begin $display("FAIL: ch6_data=%h 期望 6666", ch6_data); errors = errors + 1; end
            if (ch7_data !== 16'h7FFF) begin $display("FAIL: ch7_data=%h 期望 7FFF", ch7_data); errors = errors + 1; end
            if (ch8_data !== 16'h8000) begin $display("FAIL: ch8_data=%h 期望 8000", ch8_data); errors = errors + 1; end

            if (data_frame !== {16'h8000, 16'h7FFF, 16'h6666, 16'h5555,
                                16'h4444, 16'h3333, 16'h2222, 16'h1111}) begin
                $display("FAIL: data_frame=%h 与期望拼接不符", data_frame);
                errors = errors + 1;
            end

            if (max_channel != 4'd8) begin
                $display("FAIL: 一帧内最大通道号=%0d，期望 8", max_channel);
                errors = errors + 1;
            end

            if (ad_state !== 3'd1) begin
                $display("FAIL: 一帧结束后没有回到空闲，ad_state=%0d", ad_state);
                errors = errors + 1;
            end
        end

        // ---------------- 场景 2：FRSTDATA 缺失应报超时 ----------------
        frstdata_missing = 1'b1;
        issue_start;
        wait_timeout(20000, waited);
        if (waited < 0) begin
            $display("FAIL: FRSTDATA 缺失时没有报超时");
            errors = errors + 1;
        end
        if (data_valid !== 1'b0) begin
            $display("FAIL: FRSTDATA 缺失时仍然给出了 data_valid");
            errors = errors + 1;
        end
        frstdata_missing = 1'b0;
        repeat (20) @(posedge clk);

        // ---------------- 场景 3：BUSY 始终不拉高应报超时 ----------------
        busy_never_high = 1'b1;
        issue_start;
        wait_timeout(150000, waited);
        if (waited < 0) begin
            $display("FAIL: BUSY 始终不拉高时没有报超时");
            errors = errors + 1;
        end
        busy_never_high = 1'b0;
        repeat (20) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: AD7606_Parallel_DRIVER");
        end else begin
            $display("FAIL: AD7606_Parallel_DRIVER，共 %0d 处不符", errors);
            $fatal(1, "AD7606_Parallel_DRIVER 用例未通过");
        end
        $finish;
    end

    // 兜底：任何一个场景卡死都不至于让仿真挂着
    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
