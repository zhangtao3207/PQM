`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_adc_pacer
 * 功能:
 *   pqm_adc_pacer 的单元测试平台。被测对象是"平均严格 25.6 kHz"的采样节拍：
 *   50 MHz / 25.6 kHz = 1953.125 拍/脉冲，用 26 位累加器（增量 34361）做小数分频。
 *
 * 判定四项：
 *
 *   A. 平均频率不漂（精确判据）。
 *      取一段恰好 N 个脉冲间隔的窗口，量出它跨越的时钟拍数 S。对增量式小数分频，
 *      任何窗口都满足
 *          |S x INC - N x 2^W| <= INC          （W = 累加器位宽，INC = 增量）
 *      即 S 与实数 N x 2^W / INC 的偏差不超过 1 拍。这个判据在 64 位整数里精确可算，
 *      不用浮点，也不受窗口起止相位影响。
 *      本用例 N=1786：理论拍数 = 1786 x 2^26 / 34361 = 3488281.25 拍。
 *      注意 1 拍容差摊到 1786 个间隔上 = 每个间隔 ±0.00056 拍，所以这一项真正管的是
 *      "不漂"（约 ±0.3 Hz）；精度由 A2 的标定窗口负责。
 *
 *   A2. 标定窗口（精度的独立判据，与 A 的相位无关）。
 *      15625 拍 = 1953.125 拍/脉冲 x 8 个标称周期，应恰好含 8 个脉冲
 *      （单个脉冲周期约 1953 拍，所以 15625 拍里是 15625/1953.125 = 8 个，不是 8000 个）。
 *      这一项验证的是"15625 拍 = 8 个整周期"这个配平点，与 A 的窗口相位无关。
 *
 *   B. 抖动上界 ±1 拍：每个间隔都必须是 1953 或 1954 拍（无第三种，无漏脉冲）。
 *
 *   C. 波形干净：每次脉冲高电平恰好持续 1 拍。
 *
 *   D. 复位相位确定：复位期间 o_tick 恒为 0；复位释放后第 1954 拍出现首个脉冲
 *      （累加器从 0 起，首个使和达到/超过 2^26 的 n = ceil(2^26 / 34361) = 1954）。
 *
 * 参数（plusarg，需直调 xsim 传入；run_xsim.ps1 目前不透传）:
 *   +PULSES=<n>  窗口内脉冲间隔数，默认 1786
 *   +TCLK=<ns>   时钟周期，默认 20（50 MHz）
 *   +DBG=1       打印脉冲/间隔明细
 *
 * 注意：本用例是**纯时基**验证，不看 ADC 忙闲（pacer 不接 busy）。
 */

module tb_pqm_adc_pacer;

    // ------------------------------------------------------------------
    // 参数
    // ------------------------------------------------------------------
    integer PULSES = 1786;      // A 项窗口内脉冲间隔数
    integer TCLK   = 20;        // 时钟周期（ns）
    integer DBG    = 0;

    localparam integer ACC_W      = 26;
    localparam integer INC        = 34361;      // = 2^26 / 1953.125 四舍五入
    localparam integer MODULUS    = 67108864;   // 2^26
    localparam integer MIN_GAP    = 1953;       // 间隔下界 = floor(1953.125)
    localparam integer MAX_GAP    = 1954;       // 间隔上界 = ceil(1953.125)
    localparam integer FIRST_GAP  = 1954;       // 复位释放到首个脉冲 = ceil(2^26 / INC)
    localparam integer CAL_CYCLES = 15625;      // 标定窗口 = 8 个标称周期
    localparam integer CAL_EXPECT = 8;          // 15625 / 1953.125 = 8

    initial begin
        if ($value$plusargs("PULSES=%d", PULSES)) ;
        if ($value$plusargs("TCLK=%d", TCLK)) ;
        if ($value$plusargs("DBG=%d", DBG)) ;
    end

    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    wire o_tick;

    always #(TCLK / 2) clk = ~clk;

    pqm_adc_pacer #(
        .C_ACC_WIDTH (ACC_W),
        .C_INC       (INC)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .o_tick (o_tick)
    );

    // ------------------------------------------------------------------
    // 监视器
    // ------------------------------------------------------------------
    integer       err = 0;
    reg [63:0]    cyc = 0;              // 时钟拍计数

    integer       n_pulses    = 0;      // 复位释放后的脉冲总数
    integer       n_interval  = 0;      // 已测到的间隔数（= n_pulses - 1）
    reg [63:0]    first_cyc   = 0;      // 第 1 个脉冲所在拍
    reg [63:0]    last_cyc    = 0;      // 最近一个脉冲所在拍
    integer       min_gap     = 0;
    integer       max_gap     = 0;
    integer       n_gap_bad   = 0;

    reg           prev_rstn   = 1'b0;
    integer       high_len    = 0;
    integer       n_width_bad = 0;

    integer       n_tick_held = 0;      // 复位期间 o_tick 为高的拍数

    always @(posedge clk) begin
        cyc       <= cyc + 64'd1;
        prev_rstn <= rst_n;

        if (DBG != 0 && o_tick)
            $display("DBG pulse#%0d cyc=%0d gap=%0d", n_pulses + 1, cyc, cyc - last_cyc);

        // ---- 复位期间 o_tick 必须为 0 ----
        if (!rst_n && o_tick) n_tick_held <= n_tick_held + 1;

        // ---- 脉冲 ----
        if (rst_n && o_tick) begin
            if (n_pulses == 0) begin
                first_cyc <= cyc;
            end else begin
                if ((cyc - last_cyc) < MIN_GAP || (cyc - last_cyc) > MAX_GAP) begin
                    n_gap_bad <= n_gap_bad + 1;
                    if (DBG != 0)
                        $display("DBG gap out of spec: #%0d gap=%0d cyc=%0d",
                                 n_interval + 1, cyc - last_cyc, cyc);
                end
                if (n_interval == 0) begin
                    min_gap <= cyc - last_cyc;
                    max_gap <= cyc - last_cyc;
                end else begin
                    if ((cyc - last_cyc) < min_gap) min_gap <= cyc - last_cyc;
                    if ((cyc - last_cyc) > max_gap) max_gap <= cyc - last_cyc;
                end
                n_interval <= n_interval + 1;
            end
            last_cyc <= cyc;
            n_pulses <= n_pulses + 1;
        end

        // ---- 脉宽：高电平恰好 1 拍 ----
        if (o_tick) begin
            high_len <= high_len + 1;
        end else begin
            if (high_len > 1) n_width_bad <= n_width_bad + 1;
            high_len <= 0;
        end
    end

    // ------------------------------------------------------------------
    // 主流程
    // ------------------------------------------------------------------
    integer    i;
    integer    span_cyc;
    integer    cal_start, cal_cnt, settle, d_cnt;
    reg [63:0] lhs, rhs;

    initial begin
        // ---------------- 复位，等 500 拍 ----------------
        rst_n = 1'b0;
        repeat (500) @(posedge clk);

        // ---------------- A/B/C 项窗口 ----------------
        rst_n = 1'b1;
        while (n_interval < PULSES) @(posedge clk);

        // 读到的是非阻塞赋值前的旧值，再等 1 拍让监视器结算完
        @(posedge clk);

        span_cyc = last_cyc - first_cyc;
        lhs      = $unsigned(span_cyc) * INC;
        rhs      = $unsigned(PULSES) * MODULUS;

        $display("INFO: A 项窗口 %0d 个间隔，跨 %0d 拍（理论 %0d 拍）",
                 PULSES, span_cyc, rhs / INC);
        $display("INFO: 核账 first=%0d last=%0d pulses=%0d intervals=%0d min_gap=%0d max_gap=%0d",
                 first_cyc, last_cyc, n_pulses, n_interval, min_gap, max_gap);

        if (lhs + INC < rhs || lhs > rhs + INC) begin
            $display("FAIL: A 平均频率偏离  span=%0d 拍 / %0d 个间隔", span_cyc, PULSES);
            $display("      S x INC = %0d，N x 2^W = %0d，偏差超出 ±INC", lhs, rhs);
            err = err + 1;
        end

        if (n_interval != PULSES) begin
            $display("FAIL: 间隔数 %0d，期望 %0d", n_interval, PULSES);
            err = err + 1;
        end
        if (n_gap_bad != 0) begin
            $display("FAIL: B 有 %0d 个间隔不在 [%0d, %0d] 拍内", n_gap_bad, MIN_GAP, MAX_GAP);
            err = err + 1;
        end
        if (n_width_bad != 0) begin
            $display("FAIL: C 有 %0d 次脉冲高电平超过 1 拍", n_width_bad);
            err = err + 1;
        end

        // ---------------- A2 标定窗口 ----------------
        cal_cnt = 0;
        @(posedge clk);
        while (!o_tick) @(posedge clk);
        cal_start = cyc;
        for (settle = 0; settle < CAL_CYCLES; settle = settle + 1) begin
            @(posedge clk);
            if (o_tick) cal_cnt = cal_cnt + 1;
        end
        $display("INFO: A2 标定窗口 %0d 拍（cyc %0d -> %0d）内脉冲 %0d 个，期望 %0d ±1",
                 CAL_CYCLES, cal_start, cyc, cal_cnt, CAL_EXPECT);
        if (cal_cnt < CAL_EXPECT - 1 || cal_cnt > CAL_EXPECT + 1) begin
            $display("FAIL: A2 标定窗口内脉冲 %0d，期望 %0d ±1", cal_cnt, CAL_EXPECT);
            err = err + 1;
        end

        // ---------------- D 复位相位 ----------------
        // 主流程自己数：从复位释放那一刻起，经几个时钟上升沿才等到 o_tick。
        n_tick_held = 0;
        rst_n = 1'b0;
        repeat (200) @(posedge clk);
        if (n_tick_held != 0) begin
            $display("FAIL: D 复位期间 o_tick 拉高过 %0d 拍", n_tick_held);
            err = err + 1;
        end
        rst_n = 1'b1;
        d_cnt = 0;
        while (!o_tick) begin
            @(posedge clk);
            d_cnt = d_cnt + 1;
        end
        d_cnt = d_cnt + 1;   // 包含 o_tick 拉高的那一拍
        $display("INFO: D 复位释放到首个脉冲 = %0d 拍，期望 %0d", d_cnt, FIRST_GAP);
        if (d_cnt != FIRST_GAP) begin
            $display("FAIL: D 复位释放后首个脉冲出现在第 %0d 拍，期望 %0d", d_cnt, FIRST_GAP);
            err = err + 1;
        end

        if (err == 0) begin
            $display("PASS: pqm_adc_pacer");
        end else begin
            $display("FAIL: pqm_adc_pacer，共 %0d 处不符", err);
            $fatal(1, "pqm_adc_pacer 用例未通过");
        end
        $finish;
    end

    // 兜底看门狗（A 项窗口约 PULSES x 1953 拍 + A2 + 复位，给 4 倍余量）
    initial begin
        #(TCLK * 64'd2000 * 64'd2000);
        $display("FAIL: 仿真看门狗超时（cyc=%0d, intervals=%0d, pulses=%0d）",
                 cyc, n_interval, n_pulses);
        $fatal(1, "仿真超时");
    end

endmodule
