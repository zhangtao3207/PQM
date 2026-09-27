`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_sample_fifo_overflow
 * 功能:
 *   给 pqm_sample_fifo 的**写满/溢出路径**做独立单元验证。交接文件 §4 记着这条待办：
 *   现有用例（tb_pqm_rfg_frontend / chain）只走未满的正常流，满与溢出从没被单独验过。
 *
 *   覆盖 7 个场景，每个都给明确断言（见下）。激励一律在 @(negedge clk) 之后翻转，
 *   保证单拍脉冲正好跨一个 posedge，不会与采样撞在同一时间步；检查一律在 posedge
 *   之后（下一个 negedge 处）做，此时非阻塞赋值已结算。
 *
 *   被测模块的真实语义（读 RTL 得到，本 TB 实测确认，不是假设）：
 *     full_w  = (wr_ptr[AW] != rd_ptr[AW]) && (wr_ptr[AW-1:0] == rd_ptr[AW-1:0])
 *     empty_w = (wr_ptr == rd_ptr)
 *     do_wr   = i_wr_en && !full_w
 *     do_rd   = i_rd_en && !empty_w
 *     写满时若 i_wr_en 仍为高：该次写入被丢弃（mem 不写、wr_ptr 不动），
 *     o_overflow 置粘滞（只有 rst_n 能清）。
 *     **场景 6 实测确认**：满状态下同拍给 i_wr_en 与 i_rd_en 时，do_rd 会先腾出空间，
 *     但 do_wr 用的是**本拍**的 full_w（=1），所以这一拍写**仍被丢弃并置溢出**，
 *     不是"同时读写则写入成功"。
 *
 *   两个被测实例：
 *     u_dut   : DEPTH=64 / AW=6（默认参数，场景 1..6）
 *     u_small : DEPTH=4  / AW=2（非默认参数边界，场景 7）
 */

module tb_pqm_sample_fifo_overflow;

    localparam integer CLK_PERIOD  = 10;        // 100 MHz
    localparam integer WATCHDOG_NS = 200000;    // 20 us 兜底（本用例只用几百拍）

    localparam integer D_DEPTH = 64;            // 主被测：默认参数
    localparam integer D_AW    = 6;
    localparam integer S_DEPTH = 4;             // 边界被测：小深度
    localparam integer S_AW    = 2;

    // 数据序列（可识别、互不重叠），用于"溢出的值绝不出现在读出序列里"
    localparam [15:0] S1_BASE = 16'h1000;       // 正常流：0x1000..0x1007
    localparam [15:0] S2_BASE = 16'h2000;       // 写满：  0x2000..0x203F
    localparam [15:0] S3_BASE = 16'h3000;       // 溢出丢弃：0x3000..0x3002
    localparam [15:0] S6_BASE = 16'h4000;       // 同时读写：0x4000..0x403F
    localparam [15:0] S6_WR   = 16'h5AA5;       // 同拍被丢弃的那次写

    reg clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg rst_n   = 1'b0;
    reg rst_n_s = 1'b0;

    // ---- 主被测（DEPTH=64）激励 ----
    reg         i_wr_en = 1'b0;
    reg  [15:0] i_din   = 16'd0;
    reg         i_rd_en = 1'b0;
    wire [15:0]     o_dout;
    wire            o_empty;
    wire            o_full;
    wire            o_overflow;
    wire [D_AW:0]   o_count;

    // ---- 边界被测（DEPTH=4）激励 ----
    reg         i_wr_en_s = 1'b0;
    reg  [15:0] i_din_s   = 16'd0;
    reg         i_rd_en_s = 1'b0;
    wire [15:0]     o_dout_s;
    wire            o_empty_s;
    wire            o_full_s;
    wire            o_overflow_s;
    wire [S_AW:0]   o_count_s;

    pqm_sample_fifo #(
        .DEPTH (D_DEPTH),
        .AW    (D_AW)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_wr_en    (i_wr_en),
        .i_din      (i_din),
        .i_rd_en    (i_rd_en),
        .o_dout     (o_dout),
        .o_empty    (o_empty),
        .o_full     (o_full),
        .o_overflow (o_overflow),
        .o_count    (o_count)
    );

    pqm_sample_fifo #(
        .DEPTH (S_DEPTH),
        .AW    (S_AW)
    ) u_small (
        .clk        (clk),
        .rst_n      (rst_n_s),
        .i_wr_en    (i_wr_en_s),
        .i_din      (i_din_s),
        .i_rd_en    (i_rd_en_s),
        .o_dout     (o_dout_s),
        .o_empty    (o_empty_s),
        .o_full     (o_full_s),
        .o_overflow (o_overflow_s),
        .o_count    (o_count_s)
    );

    integer    errors     = 0;
    integer    i;
    integer    stray_cnt  = 0;      // 被丢弃的溢出值出现在读出序列里的次数
    reg [15:0] d;
    reg [255:0] tag;

    // ===================== 检查器（全部带 X 守卫） =====================
    // 注意：Verilog 里 if (X) 为假，`actual < lo || actual > hi` 这类范围比较对含 X 的值
    // 会**静默通过**。这里一律用 ===/!== 做精确比较，X/Z 天然判为不符；再显式打一条 X 提示。

    task check_bit;
        input        actual;
        input        expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: [%0t] %0s 实测 = %b%s，期望 = %b",
                         $time, tag,
                         ((^actual) === 1'bx) ? "x" : " ", actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_u16;
        input [15:0]  actual;
        input [15:0]  expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: [%0t] %0s 实测 = 0x%04h%s，期望 = 0x%04h",
                         $time, tag, actual,
                         ((^actual) === 1'bx) ? "（含 X/Z）" : "", expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_int;
        input integer actual;
        input integer expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: [%0t] %0s 实测 = %0d，期望 = %0d", $time, tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // ===================== 激励 =====================

    task idle_cycles;
        input integer n;
        begin
            repeat (n) @(negedge clk);
        end
    endtask

    // 单拍写：在 clk 低电平期间翻转，正好跨一个 posedge
    task wr1;
        input [15:0] dat;
        begin
            @(negedge clk);
            i_wr_en = 1'b1;
            i_din   = dat;
            @(negedge clk);
            i_wr_en = 1'b0;
            i_din   = 16'h0000;
        end
    endtask

    // 单拍读：o_dout = mem[rd_ptr] 是组合读，数据必须在 i_rd_en 有效的那一拍采样
    task rd1;
        output [15:0] dat;
        begin
            @(negedge clk);
            dat     = o_dout;
            i_rd_en = 1'b1;
            @(negedge clk);
            i_rd_en = 1'b0;
        end
    endtask

    task wr1_s;
        input [15:0] dat;
        begin
            @(negedge clk);
            i_wr_en_s = 1'b1;
            i_din_s   = dat;
            @(negedge clk);
            i_wr_en_s = 1'b0;
            i_din_s   = 16'h0000;
        end
    endtask

    task rd1_s;
        output [15:0] dat;
        begin
            @(negedge clk);
            dat       = o_dout_s;
            i_rd_en_s = 1'b1;
            @(negedge clk);
            i_rd_en_s = 1'b0;
        end
    endtask

    // ===================== 主流程 =====================

    initial begin
        repeat (10) @(negedge clk);
        rst_n   = 1'b1;
        rst_n_s = 1'b1;
        repeat (4) @(negedge clk);

        // ---------------------------------------------------------------
        $display("========== 复位后初始状态 ==========");
        $display("o_empty=%b o_full=%b o_count=%0d o_overflow=%b",
                 o_empty, o_full, o_count, o_overflow);
        check_bit(o_empty,    1'b1, "复位后 o_empty");
        check_bit(o_full,     1'b0, "复位后 o_full");
        check_bit(o_overflow, 1'b0, "复位后 o_overflow");
        check_int(o_count,       0, "复位后 o_count");

        // ---------------------------------------------------------------
        // 场景 1：正常流（未满）——FIFO 语义，逐点核对 o_dout
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景1：正常流（未满）写入/读出顺序 ----");
        for (i = 0; i < 8; i = i + 1) begin
            wr1(S1_BASE + i);
            $sformat(tag, "场景1 第 %0d 次写后 o_count", i);
            check_int(o_count, i + 1, tag);
            check_bit(o_empty,    1'b0, "场景1 写后 o_empty");
            check_bit(o_full,     1'b0, "场景1 写后 o_full");
            check_bit(o_overflow, 1'b0, "场景1 未满写不应置 o_overflow");
        end
        check_int(o_count, 8, "场景1 写 8 个后 o_count");
        check_bit(o_empty, 1'b0, "场景1 写 8 个后 o_empty");
        check_bit(o_full,  1'b0, "场景1 写 8 个后 o_full");

        for (i = 0; i < 8; i = i + 1) begin
            rd1(d);
            $sformat(tag, "场景1 第 %0d 个读出值", i);
            check_u16(d, S1_BASE + i, tag);            // 逐点核对：先进先出
            $sformat(tag, "场景1 第 %0d 次读后 o_count", i);
            check_int(o_count, 8 - (i + 1), tag);
            check_bit(o_empty, (i == 7) ? 1'b1 : 1'b0, "场景1 读后 o_empty");
        end
        check_int(o_count, 0, "场景1 读空后 o_count");
        check_bit(o_empty,    1'b1, "场景1 读空后 o_empty");
        check_bit(o_overflow, 1'b0, "场景1 全程不应溢出");
        $display("场景1：8 个样本 0x%04h..0x%04h 逐点核对通过，读空后 o_count=0 o_empty=1",
                 S1_BASE, S1_BASE + 7);

        // 空状态下读：do_rd = i_rd_en && !empty_w -> 不应改变任何状态
        rd1(d);
        check_int(o_count,    0,    "场景1 空读后 o_count 仍为 0");
        check_bit(o_empty,    1'b1, "场景1 空读后 o_empty 仍为 1");
        check_bit(o_full,     1'b0, "场景1 空读后 o_full 仍为 0");
        check_bit(o_overflow, 1'b0, "场景1 空读后 o_overflow 仍为 0");

        // ---------------------------------------------------------------
        // 场景 2：写满边界——连续写 DEPTH 次后 o_full 恰好拉高、o_count==DEPTH
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景2：写满边界（DEPTH=%0d） ----", D_DEPTH);
        for (i = 0; i < D_DEPTH; i = i + 1) begin
            wr1(S2_BASE + i);
            $sformat(tag, "场景2 第 %0d 次写后 o_count", i);
            check_int(o_count, i + 1, tag);
            check_bit(o_full, (i == D_DEPTH - 1) ? 1'b1 : 1'b0,
                      "场景2 第 N 次写后 o_full（只有第 DEPTH 次才应拉高）");
        end
        check_int(o_count, D_DEPTH, "场景2 写满后 o_count");
        check_bit(o_full,     1'b1, "场景2 写满后 o_full");
        check_bit(o_empty,    1'b0, "场景2 写满后 o_empty");
        check_bit(o_overflow, 1'b0, "场景2 恰好写满不应置 o_overflow");
        $display("场景2：写满 %0d 个后 o_full=%b o_count=%0d o_empty=%b o_overflow=%b",
                 D_DEPTH, o_full, o_count, o_empty, o_overflow);

        // ---------------------------------------------------------------
        // 场景 3：溢出粘滞——写满后继续写 3 次
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景3：写满后继续写 3 次 -> 溢出粘滞 ----");
        for (i = 0; i < 3; i = i + 1) begin
            wr1(S3_BASE + i);
            $sformat(tag, "场景3 溢出写 %0d 后 o_overflow", i);
            check_bit(o_overflow, 1'b1, tag);
            check_bit(o_full,     1'b1, "场景3 溢出写后 o_full 仍为 1");
            check_bit(o_empty,    1'b0, "场景3 溢出写后 o_empty 仍为 0");
            $sformat(tag, "场景3 溢出写 %0d 后 o_count（写被丢弃，指针不动）", i);
            check_int(o_count, D_DEPTH, tag);
            $display("场景3 第 %0d 次溢出写：o_overflow=%b o_count=%0d o_full=%b",
                     i, o_overflow, o_count, o_full);
        end

        // 粘滞性：长时间无写请求也不自清（只有 rst_n 能清）
        idle_cycles(20);
        check_bit(o_overflow, 1'b1, "场景3 空闲 20 拍后 o_overflow 仍应粘滞为 1");
        check_int(o_count, D_DEPTH, "场景3 空闲后 o_count 仍为 DEPTH");
        $display("场景3：空闲 20 拍后 o_overflow=%b（粘滞，未自清）", o_overflow);

        // ---------------------------------------------------------------
        // 场景 4：溢出不污染数据——溢出的值绝不出现，且已存数据不被覆盖
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景4：溢出丢弃的值绝不出现在读出序列 ----");
        stray_cnt = 0;
        for (i = 0; i < D_DEPTH; i = i + 1) begin
            rd1(d);
            $sformat(tag, "场景4 第 %0d 个读出值（应为 0x%04h）", i, S2_BASE + i);
            check_u16(d, S2_BASE + i, tag);
            if ((d === S3_BASE) || (d === S3_BASE + 1) || (d === S3_BASE + 2))
                stray_cnt = stray_cnt + 1;      // 溢出的那 3 个值绝不该被读出
        end
        check_int(stray_cnt, 0, "场景4 溢出值出现在读出序列里的次数");
        check_int(o_count,    0,    "场景4 读空后 o_count");
        check_bit(o_empty,    1'b1, "场景4 读空后 o_empty");
        check_bit(o_full,     1'b0, "场景4 读空后 o_full");
        $display("场景4：%0d 个值 0x%04h..0x%04h 逐点符合，溢出值 0x%04h..0x%04h 出现 %0d 次",
                 D_DEPTH, S2_BASE, S2_BASE + D_DEPTH - 1, S3_BASE, S3_BASE + 2, stray_cnt);

        // ---------------------------------------------------------------
        // 场景 5：rst_n 清溢出、清指针
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景5：rst_n 拉低再拉高 -> o_overflow 归零、指针归零 ----");
        @(negedge clk);
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        check_bit(o_overflow, 1'b0, "场景5 复位期间 o_overflow");
        check_int(o_count,    0,    "场景5 复位期间 o_count");
        check_bit(o_empty,    1'b1, "场景5 复位期间 o_empty");
        check_bit(o_full,     1'b0, "场景5 复位期间 o_full");
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);
        check_bit(o_overflow, 1'b0, "场景5 复位释放后 o_overflow 归零");
        check_int(o_count,    0,    "场景5 复位释放后 o_count 归零");
        check_bit(o_empty,    1'b1, "场景5 复位释放后 o_empty 拉高");
        check_bit(o_full,     1'b0, "场景5 复位释放后 o_full 为低");
        $display("场景5：复位释放后 o_overflow=%b o_count=%0d o_empty=%b o_full=%b",
                 o_overflow, o_count, o_empty, o_full);

        // ---------------------------------------------------------------
        // 场景 6：满状态下同时读写（本模块的真实语义，实测确认）
        //   同一拍 i_wr_en=1 且 i_rd_en=1：do_rd 会执行（腾出 1 个空位），
        //   但 do_wr = i_wr_en && !full_w 用的是**本拍**的 full_w=1，
        //   所以这次写被丢弃，o_overflow 置起。=> 同拍读写不等于写入成功。
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景6：满状态下同时读写（实测语义） ----");
        for (i = 0; i < D_DEPTH; i = i + 1) wr1(S6_BASE + i);
        check_bit(o_full,     1'b1, "场景6 填满后 o_full");
        check_int(o_count, D_DEPTH, "场景6 填满后 o_count");
        check_bit(o_overflow, 1'b0, "场景6 填满过程不应溢出");

        @(negedge clk);
        d       = o_dout;          // 同拍组合读数据（此时应为最早写入的 0x4000）
        i_wr_en = 1'b1;
        i_din   = S6_WR;
        i_rd_en = 1'b1;
        @(negedge clk);            // 中间一个 posedge 执行
        i_wr_en = 1'b0;
        i_rd_en = 1'b0;
        i_din   = 16'h0000;

        $display("场景6 同拍读写后：o_overflow=%b o_count=%0d o_full=%b o_empty=%b 同拍读出=0x%04h",
                 o_overflow, o_count, o_full, o_empty, d);
        check_u16(d, S6_BASE, "场景6 同拍读到的数据（最早的 0x4000）");
        check_bit(o_overflow, 1'b1, "场景6 同拍写被丢弃 -> o_overflow 置起（实测语义）");
        check_int(o_count, D_DEPTH - 1, "场景6 同拍后 o_count（读走 1 个、写被丢弃）");
        check_bit(o_full,  1'b0, "场景6 同拍后 o_full（已腾出 1 个空位）");
        check_bit(o_empty, 1'b0, "场景6 同拍后 o_empty");

        // 余下 63 个数据与顺序都必须完好，被丢弃的 0x5AA5 绝不出现
        stray_cnt = 0;
        for (i = 0; i < D_DEPTH - 1; i = i + 1) begin
            rd1(d);
            $sformat(tag, "场景6 余下第 %0d 个读出值（应为 0x%04h）", i, S6_BASE + 1 + i);
            check_u16(d, S6_BASE + 1 + i, tag);
            if (d === S6_WR) stray_cnt = stray_cnt + 1;
        end
        check_int(stray_cnt, 0, "场景6 被丢弃的 0x5AA5 出现在读出序列里的次数");
        check_bit(o_empty, 1'b1, "场景6 读空后 o_empty");
        check_int(o_count, 0,    "场景6 读空后 o_count");
        $display("场景6：余下 %0d 个值 0x%04h..0x%04h 完好，被丢弃的 0x%04h 出现 %0d 次",
                 D_DEPTH - 1, S6_BASE + 1, S6_BASE + D_DEPTH - 1, S6_WR, stray_cnt);

        // ---------------------------------------------------------------
        // 场景 7：非默认参数（DEPTH=4 / AW=2）的满/空判据
        // ---------------------------------------------------------------
        $display("");
        $display("---- 场景7：DEPTH=%0d / AW=%0d 的满/空判据 ----", S_DEPTH, S_AW);
        check_int(o_count_s,  0,    "场景7 复位后 o_count_s");
        check_bit(o_empty_s,  1'b1, "场景7 复位后 o_empty_s");
        check_bit(o_full_s,   1'b0, "场景7 复位后 o_full_s");
        check_bit(o_overflow_s, 1'b0, "场景7 复位后 o_overflow_s");

        for (i = 0; i < S_DEPTH; i = i + 1) begin
            wr1_s(16'h0010 * (i + 1));          // 0x10 0x20 0x30 0x40
            $sformat(tag, "场景7 第 %0d 次写后 o_count_s", i);
            check_int(o_count_s, i + 1, tag);
            check_bit(o_full_s, (i == S_DEPTH - 1) ? 1'b1 : 1'b0,
                      "场景7 第 N 次写后 o_full_s（只有第 DEPTH 次才应拉高）");
        end
        check_int(o_count_s, S_DEPTH, "场景7 写满后 o_count_s");
        check_bit(o_full_s,  1'b1, "场景7 写满后 o_full_s");
        check_bit(o_empty_s, 1'b0, "场景7 写满后 o_empty_s");

        wr1_s(16'h0050);                        // 满后再写一次 -> 丢弃 + 溢出
        check_bit(o_overflow_s, 1'b1, "场景7 溢出后 o_overflow_s");
        check_int(o_count_s, S_DEPTH, "场景7 溢出写后 o_count_s 不变");
        check_bit(o_full_s,  1'b1, "场景7 溢出写后 o_full_s 仍为 1");

        stray_cnt = 0;
        for (i = 0; i < S_DEPTH; i = i + 1) begin
            rd1_s(d);
            $sformat(tag, "场景7 第 %0d 个读出值（应为 0x%04h）", i, 16'h0010 * (i + 1));
            check_u16(d, 16'h0010 * (i + 1), tag);
            if (d === 16'h0050) stray_cnt = stray_cnt + 1;
        end
        check_int(stray_cnt,  0,    "场景7 溢出值 0x0050 出现在读出序列里的次数");
        check_bit(o_empty_s,  1'b1, "场景7 读空后 o_empty_s");
        check_int(o_count_s,  0,    "场景7 读空后 o_count_s");
        check_bit(o_full_s,   1'b0, "场景7 读空后 o_full_s");
        $display("场景7：DEPTH=%0d 满判据、溢出丢弃、读出顺序（含 0x0050 未出现）全部通过",
                 S_DEPTH);

        // ---------------------------------------------------------------
        $display("");
        if (errors == 0) begin
            $display("PASS: pqm_sample_fifo_overflow");
        end else begin
            $display("FAIL: pqm_sample_fifo_overflow，共 %0d 处不符", errors);
            $fatal(1, "pqm_sample_fifo_overflow 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
