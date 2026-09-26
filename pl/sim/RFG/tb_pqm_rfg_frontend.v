`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_rfg_frontend
 * 功能:
 *   RFG 版频域前端的端到端验证：喂「512 点 = 一个 50 Hz 周期」的已知多谐波波形，
 *   核对输出顺序流（0 次直流 + 1..64 次）的复数结果与解析值。
 *
 *   激励（Q2.14，512 点，由 pl/sim/RFG/front_end_vectors 生成）：
 *     u[n] = 1000*cos(2*pi*n/512) + 400*cos(6*pi*n/512)   即 1 次 1000 + 3 次 400
 *     i[n] =  800*sin(2*pi*n/512)                          即 1 次 800、滞后 90°
 *   两路都是零均值 -> 直流应为 0。
 *
 *   期望值（RFG 标度：output = 2 * Σ(x*W)，x 为 Q2.14 整数）：
 *     u: X(1) = 1000*512 = 512000 + j0
 *        X(3) =  400*512 = 204800 + j0
 *     i: X(1) = 0 - j800*512 = 0 - j409600      （sin 的 DFT 是 -j*A*N/2）
 *     0 次：两路都 = 0；其余次 ≈ 0
 *
 *   同时验证前端的三条结构性要求：
 *     - 顺序流以 0 次开头、次数严格递增 0..64（直流优先仲裁有效）
 *     - 末项（64 次）带 o_item_last，握手完成后 o_frame_done 拉高
 *     - o_channel_error 恒 0（两通道 bin 号始终一致）、o_overflow 恒 0
 */

module tb_pqm_rfg_frontend;

    localparam integer CLK_PERIOD  = 10;       // 100 MHz
    localparam integer WATCHDOG_NS = 20000000; // 20 ms 兜底
    localparam integer C_N         = 512;
    localparam integer C_K         = 64;
    localparam integer C_L         = 4;
    localparam integer C_D         = 1;
    localparam integer ITEMS       = C_K + 1;  // 0 次 + 1..64 次
    localparam integer TOL_MAIN    = 6144;     // 主频点容差（含输入量化与 Q2.24 旋转误差）
    localparam integer TOL_QUIET   = 8192;     // 静默频点容差
    localparam integer TOL_DC      = 64;       // 直流容差（零均值，应几乎为 0）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg        i_start = 1'b0;
    reg        i_sample_valid = 1'b0;
    reg [15:0] i_sample_u = 16'd0;
    reg [15:0] i_sample_i = 16'd0;
    wire [15:0] i_zero_code = 16'd0;
    reg        i_item_ready = 1'b1;

    wire        o_sample_ready;
    wire        o_item_valid;
    wire [8:0]  o_order;
    wire signed [31:0] o_u_real, o_u_imag, o_i_real, o_i_imag;
    wire        o_item_last;
    wire        o_frame_done;
    wire        o_overflow;
    wire        o_channel_error;

    reg [15:0] u_tab [0:C_N-1];
    reg [15:0] i_tab [0:C_N-1];

    integer errors = 0;
    integer i;
    integer item_cnt       = 0;
    integer last_order     = -1;
    integer order_err      = 0;
    integer last_flag_err  = 0;
    integer chan_err_seen  = 0;
    integer last_seen_at   = -1;
    reg     frame_done_seen = 1'b0;
    reg     last_seen       = 1'b0;

    integer ur [0:ITEMS-1];
    integer ui [0:ITEMS-1];
    integer ir [0:ITEMS-1];
    integer ii [0:ITEMS-1];

    pqm_rfg_frontend #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .i_start(i_start), .i_sample_valid(i_sample_valid),
        .i_sample_u(i_sample_u), .i_sample_i(i_sample_i),
        .i_zero_code(i_zero_code),
        .o_sample_ready(o_sample_ready),
        .o_item_valid(o_item_valid), .i_item_ready(i_item_ready),
        .o_order(o_order),
        .o_u_real(o_u_real), .o_u_imag(o_u_imag),
        .o_i_real(o_i_real), .o_i_imag(o_i_imag),
        .o_item_last(o_item_last),
        .o_frame_done(o_frame_done),
        .o_overflow(o_overflow),
        .o_channel_error(o_channel_error)
    );

    // 收顺序流，记录次序错误与帧尾
    always @(posedge clk) begin
        if (rst_n && o_item_valid && i_item_ready) begin
            // 注意：o_order 是无符号线网，与 integer 的 -1 比较会被当成 0xFFFFFFFF，
            // 所以首项必须用 item_cnt 判掉，不能靠 last_order=-1 兜底。
            if (item_cnt != 0 && o_order <= last_order) order_err = order_err + 1;
            last_order = o_order;
            if (item_cnt < ITEMS) begin
                ur[o_order] = $signed(o_u_real);
                ui[o_order] = $signed(o_u_imag);
                ir[o_order] = $signed(o_i_real);
                ii[o_order] = $signed(o_i_imag);
            end
            if (o_item_last) begin
                last_seen    = 1'b1;
                last_seen_at = item_cnt;
            end
            item_cnt = item_cnt + 1;
        end
        if (rst_n && o_frame_done)       frame_done_seen <= 1'b1;
        if (rst_n && o_channel_error)    chan_err_seen   = chan_err_seen + 1;
    end

    // 照抄厂商 TB 的驱动时序
    task automatic start_frame;
        integer g;
        begin
            @(negedge clk); i_start = 1'b1;
            @(negedge clk); i_start = 1'b0;
            g = 0;
            while (!o_sample_ready && g < 200000) begin @(negedge clk); g = g + 1; end
            if (!o_sample_ready) begin
                $display("FAIL: start 之后 o_sample_ready 一直不拉高");
                errors = errors + 1;
            end
        end
    endtask

    task automatic drive_samples;
        integer k; integer g;
        begin
            k = 0; g = 0;
            while (k < C_N && g < 4000000) begin
                @(negedge clk);
                g = g + 1;
                i_start = 1'b0;
                if (o_sample_ready) begin
                    i_sample_valid = 1'b1;
                    i_sample_u     = u_tab[k];
                    i_sample_i     = i_tab[k];
                    k = k + 1;
                end else begin
                    i_sample_valid = 1'b0;
                end
            end
            if (k < C_N) begin
                $display("FAIL: 只送出 %0d 个样本（期望 %0d）", k, C_N);
                errors = errors + 1;
            end
            @(negedge clk);
            i_sample_valid = 1'b0;
        end
    endtask

    task automatic wait_frame;
        integer g;
        begin
            g = 0;
            while (!(frame_done_seen && item_cnt >= ITEMS) && g < 4000000) begin
                @(posedge clk); g = g + 1;
            end
            if (!(frame_done_seen && item_cnt >= ITEMS)) begin
                $display("FAIL: 等不到帧结束（item_cnt=%0d frame_done=%0b）", item_cnt, frame_done_seen);
                errors = errors + 1;
            end
            repeat (10) @(posedge clk);
        end
    endtask

    task check_val;
        input integer actual;
        input integer expected;
        input integer tol;
        input [255:0] tag;
        begin
            if (^actual === 1'bx) begin
                $display("FAIL: %0s = X（未初始化/未驱动）", tag);
                errors = errors + 1;
            end else if (actual < expected - tol || actual > expected + tol) begin
                $display("FAIL: %0s = %0d，期望 %0d ± %0d", tag, actual, expected, tol);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $readmemh("u_q14.hex", u_tab);
        $readmemh("i_q14.hex", i_tab);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        start_frame;
        item_cnt   = 0;
        last_order = -1;
        drive_samples;
        wait_frame;

        $display("");
        $display("========== RFG 前端端到端（1 次 1000 + 3 次 400 的 u；1 次 800 滞后 90° 的 i） ==========");
        $display("输出项数 = %0d（期望 %0d），次序错误 = %0d，帧尾在 item#%0d，channel_error = %0d，overflow = %0b",
                 item_cnt, ITEMS, order_err, last_seen_at, chan_err_seen, o_overflow);
        $display("次数 :        u_re      u_im      i_re      i_im");
        for (i = 0; i <= 6; i = i + 1)
            $display("  %0d  : %9d %9d %9d %9d", i, ur[i], ui[i], ir[i], ii[i]);
        $display("  ... (7..64 略)");
        $display("  64  : %9d %9d %9d %9d", ur[64], ui[64], ir[64], ii[64]);

        // 结构
        if (item_cnt != ITEMS) begin
            $display("FAIL: 输出项数 %0d，期望 %0d", item_cnt, ITEMS);
            errors = errors + 1;
        end
        if (order_err != 0) begin
            $display("FAIL: 次数没有严格递增，出现 %0d 次", order_err);
            errors = errors + 1;
        end
        if (last_seen_at != ITEMS - 1) begin
            $display("FAIL: o_item_last 出现在 item#%0d，期望 %0d", last_seen_at, ITEMS - 1);
            errors = errors + 1;
        end
        if (chan_err_seen != 0) begin
            $display("FAIL: 两通道 bin 号不一致 %0d 次", chan_err_seen);
            errors = errors + 1;
        end
        if (o_overflow !== 1'b0) begin
            $display("FAIL: RFG 报溢出");
            errors = errors + 1;
        end

        // 数值
        check_val(ur[0], 0, TOL_DC,   "0 次 u_re");
        check_val(ui[0], 0, TOL_DC,   "0 次 u_im");
        check_val(ir[0], 0, TOL_DC,   "0 次 i_re");
        check_val(ii[0], 0, TOL_DC,   "0 次 i_im");
        check_val(ur[1],  512000, TOL_MAIN, "1 次 u_re");
        check_val(ui[1],       0, TOL_MAIN, "1 次 u_im");
        check_val(ir[1],       0, TOL_MAIN, "1 次 i_re");
        check_val(ii[1], -409600, TOL_MAIN, "1 次 i_im");
        check_val(ur[3],  204800, TOL_MAIN, "3 次 u_re");
        check_val(ui[3],       0, TOL_MAIN, "3 次 u_im");
        check_val(ir[3],       0, TOL_QUIET, "3 次 i_re");
        check_val(ii[3],       0, TOL_QUIET, "3 次 i_im");
        for (i = 2; i <= C_K; i = i + 1) begin
            if (i == 3) continue;
            check_val(ur[i], 0, TOL_QUIET, "静默次 u_re");
            check_val(ui[i], 0, TOL_QUIET, "静默次 u_im");
            check_val(ir[i], 0, TOL_QUIET, "静默次 i_re");
            check_val(ii[i], 0, TOL_QUIET, "静默次 i_im");
        end

        if (errors == 0) begin
            $display("");
            $display("PASS: pqm_rfg_frontend");
        end else begin
            $display("FAIL: pqm_rfg_frontend，共 %0d 处不符", errors);
            $fatal(1, "pqm_rfg_frontend 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
