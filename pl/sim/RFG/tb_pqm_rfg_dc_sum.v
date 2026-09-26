`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_rfg_dc_sum
 * 功能:
 *   验证 pqm_rfg_dc_sum 给出的 0 次（直流）分量与 RFG 的 bin 输出**标度一致**、
 *   且与 RFG 的一帧严格对齐。这是"用最小代价解决 bin 0"的关键证据：
 *   RFG 只输出 1..K，直流必须自己补，否则第 1 页那条 0 次没有数据源；
 *   而下游占比是 mag*10000/total，直流与谐波必须同标度才能一起算。
 *
 *   驱动时序**逐条照抄厂商 TB**（tb_e01_rfg_l4_optimization 的 start_frame /
 *   drive_samples）：start 一拍 -> 先等 o_sample_ready 拉高 -> 之后每个被接收的
 *   样本只在 ready 为高的那一拍给 valid。不能用 wait(!o_busy)：o_busy 在复位前后
 *   可能是 X，会直接把仿真挂死（第一次就这么挂到看门狗）。
 *
 *   两组激励（零点取 0，所以 centered = sample）：
 *     1) 冲激：n=0 为 16384（=1.0 的 Q2.14），其余为 0
 *        理论：Σx = 16384 -> 直流 = 2*16384 = 32768；
 *              RFG 所有 bin 也是 2*16384 = 32768（冲激谱平坦）
 *        判据：**直流与各 bin 相等** -> 标度对齐
 *     2) 纯直流：全部 512 个样本都是 16384
 *        理论：Σx = 512*16384 = 8388608 -> 直流 = 16777216；
 *              RFG 的 1..64 次应接近 0（直流没有交流能量）
 *        判据：直流正好等于那个值，且各 bin 都很小 -> 直流与 1..K 互补不重叠
 */

module tb_pqm_rfg_dc_sum;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 20000000;// 20 ms 兜底（RFG 一帧约 84k 拍，两帧足够）
    localparam integer C_N         = 512;
    localparam integer C_K         = 64;
    localparam integer C_L         = 4;
    localparam integer C_D         = 1;
    localparam integer AMP         = 16384;   // 1.0 in Q2.14
    localparam integer TOL_BIN     = 256;
    localparam integer TOL_QUIET   = 2048;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg        scenario = 1'b0;      // 0=冲激, 1=纯直流
    reg        i_start = 1'b0;
    reg        i_sample_valid = 1'b0;
    reg [15:0] i_sample = 16'd0;
    wire [15:0] i_zero_code = 16'd0;
    reg        i_result_ready = 1'b1;

    wire        o_sample_ready;
    wire        o_busy;
    wire        o_result_valid;
    wire [8:0]  o_bin_index;
    wire signed [31:0] o_result_real;
    wire signed [31:0] o_result_imag;
    wire        o_result_last;
    wire        o_frame_done;
    wire        o_overflow;

    wire signed [31:0] dc_q15;
    wire               dc_valid;
    wire [15:0]        dc_frame_count;

    integer errors = 0;
    integer i;
    integer bin_re [0:C_K-1];
    integer bin_im [0:C_K-1];
    integer result_cnt = 0;
    integer dc_seen = 0;
    integer dc_value = 0;
    reg     frame_seen = 1'b0;      // o_frame_done 是单拍脉冲，必须锁存后与 result_cnt 一起判

    e01_rfg_nkld_top #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D), .C_BACKEND(0)
    ) u_rfg (
        .sys_clk        (clk),
        .rst_n          (rst_n),
        .i_start        (i_start),
        .i_sample_valid (i_sample_valid),
        .i_sample       (i_sample),
        .i_result_ready (i_result_ready),
        .o_sample_ready (o_sample_ready),
        .o_busy         (o_busy),
        .o_result_valid (o_result_valid),
        .o_bin_index    (o_bin_index),
        .o_result_real  (o_result_real),
        .o_result_imag  (o_result_imag),
        .o_result_last  (o_result_last),
        .o_frame_done   (o_frame_done),
        .o_overflow     (o_overflow)
    );

    pqm_rfg_dc_sum #(.C_N(C_N)) u_dc (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_start        (i_start),
        .i_sample_valid (i_sample_valid),
        .i_sample_ready (o_sample_ready),
        .i_sample       (i_sample),
        .i_zero_code    (i_zero_code),
        .o_dc_q15       (dc_q15),
        .o_dc_valid     (dc_valid),
        .o_frame_count  (dc_frame_count)
    );

    // 收结果（i_result_ready 常高）
    always @(posedge clk) begin
        if (rst_n && o_result_valid && i_result_ready) begin
            bin_re[o_bin_index[5:0] - 6'd1] = $signed(o_result_real);
            bin_im[o_bin_index[5:0] - 6'd1] = $signed(o_result_imag);
            result_cnt = result_cnt + 1;
        end
        if (rst_n && o_frame_done)
            frame_seen <= 1'b1;
        if (rst_n && dc_valid) begin
            dc_value = $signed(dc_q15);
            dc_seen  = dc_seen + 1;
        end
    end

    // 照抄厂商 TB：start 一拍，然后等 ready
    task automatic start_frame;
        integer g;
        begin
            @(negedge clk);
            i_start = 1'b1;
            @(negedge clk);
            i_start = 1'b0;

            g = 0;
            while (!o_sample_ready && g < 200000) begin
                @(negedge clk);
                g = g + 1;
            end
            if (!o_sample_ready) begin
                $display("FAIL: start 之后 o_sample_ready 一直不拉高");
                errors = errors + 1;
            end
        end
    endtask

    // 照抄厂商 TB：valid 只在 ready 高的那一拍给，给满 C_N 个
    task automatic drive_samples;
        integer k;
        integer g;
        begin
            k = 0;
            g = 0;
            while (k < C_N && g < 4000000) begin
                @(negedge clk);
                g = g + 1;
                i_start = 1'b0;
                if (o_sample_ready) begin
                    i_sample_valid = 1'b1;
                    if (scenario == 1'b0)
                        i_sample = (k == 0) ? AMP[15:0] : 16'd0;   // 冲激
                    else
                        i_sample = AMP[15:0];                      // 纯直流
                    k = k + 1;
                end else begin
                    i_sample_valid = 1'b0;
                    i_sample       = 16'd0;
                end
            end
            if (k < C_N) begin
                $display("FAIL: 只送出 %0d 个样本（期望 %0d）", k, C_N);
                errors = errors + 1;
            end
            @(negedge clk);
            i_start        = 1'b0;
            i_sample_valid = 1'b0;
            i_sample       = 16'd0;
        end
    endtask

    task automatic wait_results;
        integer g;
        begin
            g = 0;
            while (!(frame_seen && result_cnt >= C_K) && g < 4000000) begin
                @(posedge clk);
                g = g + 1;
            end
            if (!(frame_seen && result_cnt >= C_K)) begin
                $display("FAIL: 等不到 o_frame_done / 结果收齐（result_cnt=%0d）", result_cnt);
                errors = errors + 1;
            end
            repeat (10) @(posedge clk);
        end
    endtask

    task automatic run_frame;
        begin
            start_frame;
            frame_seen = 1'b0;
            result_cnt = 0;
            for (i = 0; i < C_K; i = i + 1) begin bin_re[i] = 0; bin_im[i] = 0; end
            drive_samples;
            wait_results;
        end
    endtask

    task check_range;
        input integer actual;
        input integer lo;
        input integer hi;
        input [255:0] tag;
        begin
            if (^actual === 1'bx) begin
                $display("FAIL: %0s = X（未初始化/未驱动）", tag);
                errors = errors + 1;
            end else if (actual < lo || actual > hi) begin
                $display("FAIL: %0s = %0d，期望落在 [%0d, %0d]", tag, actual, lo, hi);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);
        $display("复位后：o_busy=%b o_sample_ready=%b o_frame_done=%b", o_busy, o_sample_ready, o_frame_done);

        // ---------------- 场景 1：冲激 ----------------
        scenario = 1'b0;
        dc_seen  = 0;
        run_frame;

        $display("");
        $display("========== 场景1 冲激（n=0 为 16384） ==========");
        $display("直流        = %0d（理论 2*16384 = 32768）", dc_value);
        $display("bin1..6 实部 = %0d %0d %0d %0d %0d %0d", bin_re[0],bin_re[1],bin_re[2],bin_re[3],bin_re[4],bin_re[5]);
        $display("bin1..6 虚部 = %0d %0d %0d %0d %0d %0d", bin_im[0],bin_im[1],bin_im[2],bin_im[3],bin_im[4],bin_im[5]);
        $display("结果数 = %0d（期望 %0d），dc_valid 次数 = %0d，溢出 = %0b",
                 result_cnt, C_K, dc_seen, o_overflow);

        check_range(dc_value, 2*AMP - TOL_BIN, 2*AMP + TOL_BIN, "冲激直流");
        for (i = 0; i < C_K; i = i + 1)
            check_range(bin_re[i], 2*AMP - TOL_BIN, 2*AMP + TOL_BIN, "冲激 bin 实部");
        if (dc_seen != 1) begin
            $display("FAIL: 一帧应只出一次 o_dc_valid，实际 %0d", dc_seen);
            errors = errors + 1;
        end
        if (o_overflow !== 1'b0) begin
            $display("FAIL: RFG 报溢出");
            errors = errors + 1;
        end
        if (dc_frame_count !== 16'd1) begin
            $display("FAIL: 直流模块帧计数 = %0d，期望 1", dc_frame_count);
            errors = errors + 1;
        end

        // ---------------- 场景 2：纯直流 ----------------
        scenario = 1'b1;
        dc_seen  = 0;
        run_frame;

        $display("");
        $display("========== 场景2 纯直流（全部 16384） ==========");
        $display("直流        = %0d（理论 2*512*16384 = 16777216）", dc_value);
        $display("bin1..6 实部 = %0d %0d %0d %0d %0d %0d", bin_re[0],bin_re[1],bin_re[2],bin_re[3],bin_re[4],bin_re[5]);
        $display("bin1..6 虚部 = %0d %0d %0d %0d %0d %0d", bin_im[0],bin_im[1],bin_im[2],bin_im[3],bin_im[4],bin_im[5]);
        $display("结果数 = %0d，dc_valid 次数 = %0d，帧计数 = %0d", result_cnt, dc_seen, dc_frame_count);

        check_range(dc_value, 2*C_N*AMP - 64, 2*C_N*AMP + 64, "纯直流直流");
        for (i = 0; i < C_K; i = i + 1) begin
            check_range(bin_re[i], -TOL_QUIET, TOL_QUIET, "纯直流 bin 实部");
            check_range(bin_im[i], -TOL_QUIET, TOL_QUIET, "纯直流 bin 虚部");
        end
        if (dc_seen != 1) begin
            $display("FAIL: 第二帧应只出一次 o_dc_valid，实际 %0d", dc_seen);
            errors = errors + 1;
        end
        if (dc_frame_count !== 16'd2) begin
            $display("FAIL: 直流模块帧计数 = %0d，期望 2", dc_frame_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("");
            $display("PASS: pqm_rfg_dc_sum");
        end else begin
            $display("FAIL: pqm_rfg_dc_sum，共 %0d 处不符", errors);
            $fatal(1, "pqm_rfg_dc_sum 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
