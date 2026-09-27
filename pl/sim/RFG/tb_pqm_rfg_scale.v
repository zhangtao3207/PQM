`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_rfg_scale
 * 功能:
 *   frontend -> scale 串联验证：确认缩放后的 16 位频点流（形状与
 *   原 FFT 链接收器（已删）的输出一致）数值正确，可以直接喂给现有的
 *   magnitude_calc / harmonic_stats 等已验证模块。
 *
 *   激励同 tb_pqm_rfg_frontend：
 *     u[n] = 1000*cos(2*pi*n/512) + 400*cos(6*pi*n/512)
 *     i[n] =  800*sin(2*pi*n/512)
 *   RFG 侧理论值 -> 右移 10 位后的期望：
 *     0 次：0
 *     1 次 u：512000>>10 = 500，虚部 -29>>10 = -1（算术右移向下取整）
 *     1 次 i：-104>>10 = -1，-409632>>10 = -401（理论 -409600>>10 = -400）
 *     3 次 u：204813>>10 = 200
 *     其余次：|值| <= 24 -> 右移后全 0
 */

module tb_pqm_rfg_scale;

    localparam integer CLK_PERIOD  = 10;
    localparam integer WATCHDOG_NS = 20000000;
    localparam integer C_N         = 512;
    localparam integer C_K         = 64;
    localparam integer C_L         = 4;
    localparam integer C_D         = 1;
    localparam integer ITEMS       = C_K + 1;
    localparam integer SHIFT       = 10;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg        i_start = 1'b0;
    reg        i_sample_valid = 1'b0;
    reg [15:0] i_sample_u = 16'd0;
    reg [15:0] i_sample_i = 16'd0;
    wire [15:0] i_zero_code = 16'd0;

    // frontend 的 32 位流
    wire        fe_item_valid;
    wire        fe_item_ready;
    wire [8:0]  fe_order;
    wire signed [31:0] fe_u_real, fe_u_imag, fe_i_real, fe_i_imag;
    wire        fe_item_last;
    wire        fe_frame_done, fe_sample_ready, fe_overflow, fe_channel_error;

    // scale 之后的 16 位流（下游形状）
    wire        m_bin_valid;
    reg         m_bin_ready = 1'b1;
    wire        m_bin_last;
    wire [10:0] m_bin_index;
    wire signed [15:0] m_u_real, m_u_imag, m_i_real, m_i_imag;
    wire        sc_frame_done;

    reg [15:0] u_tab [0:C_N-1];
    reg [15:0] i_tab [0:C_N-1];

    integer errors = 0;
    integer i;
    integer item_cnt      = 0;
    integer last_order    = -1;
    integer order_err     = 0;
    integer last_seen_at  = -1;
    integer ur [0:ITEMS-1];
    integer ui [0:ITEMS-1];
    integer ir [0:ITEMS-1];
    integer ii [0:ITEMS-1];
    reg     frame_done_seen = 1'b0;

    pqm_rfg_frontend #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D)
    ) u_fe (
        .clk(clk), .rst_n(rst_n),
        .i_start(i_start), .i_sample_valid(i_sample_valid),
        .i_sample_u(i_sample_u), .i_sample_i(i_sample_i),
        .i_zero_code(i_zero_code),
        .o_sample_ready(fe_sample_ready),
        .o_item_valid(fe_item_valid), .i_item_ready(fe_item_ready),
        .o_order(fe_order),
        .o_u_real(fe_u_real), .o_u_imag(fe_u_imag),
        .o_i_real(fe_i_real), .o_i_imag(fe_i_imag),
        .o_item_last(fe_item_last),
        .o_frame_done(fe_frame_done),
        .o_overflow(fe_overflow),
        .o_channel_error(fe_channel_error)
    );

    pqm_rfg_scale #(.C_K(C_K), .SHIFT(SHIFT)) u_sc (
        .clk(clk), .rst_n(rst_n), .i_start(i_start),
        .i_item_valid(fe_item_valid), .o_item_ready(fe_item_ready),
        .i_order(fe_order),
        .i_u_real(fe_u_real), .i_u_imag(fe_u_imag),
        .i_i_real(fe_i_real), .i_i_imag(fe_i_imag),
        .i_item_last(fe_item_last),
        .m_bin_valid(m_bin_valid), .m_bin_ready(m_bin_ready),
        .m_bin_last(m_bin_last), .m_bin_index(m_bin_index),
        .m_u_real(m_u_real), .m_u_imag(m_u_imag),
        .m_i_real(m_i_real), .m_i_imag(m_i_imag),
        .o_frame_done(sc_frame_done)
    );

    always @(posedge clk) begin
        if (rst_n && m_bin_valid && m_bin_ready) begin
            if (item_cnt < 3)
                $display("diag item#%0d: fe_order=%b m_bin_index=%b fe_u_real=%b m_u_real=%b",
                         item_cnt, fe_order, m_bin_index, fe_u_real, m_u_real);
            if (item_cnt != 0 && m_bin_index[8:0] <= last_order) order_err = order_err + 1;
            last_order = m_bin_index[8:0];
            if (item_cnt < ITEMS) begin
                ur[m_bin_index[8:0]] = $signed(m_u_real);
                ui[m_bin_index[8:0]] = $signed(m_u_imag);
                ir[m_bin_index[8:0]] = $signed(m_i_real);
                ii[m_bin_index[8:0]] = $signed(m_i_imag);
            end
            if (m_bin_last) last_seen_at = item_cnt;
            item_cnt = item_cnt + 1;
        end
        if (rst_n && sc_frame_done) frame_done_seen <= 1'b1;
    end

    task automatic start_frame;
        integer g;
        begin
            @(negedge clk); i_start = 1'b1;
            @(negedge clk); i_start = 1'b0;
            g = 0;
            while (!fe_sample_ready && g < 200000) begin @(negedge clk); g = g + 1; end
            if (!fe_sample_ready) begin
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
                if (fe_sample_ready) begin
                    i_sample_valid = 1'b1;
                    i_sample_u     = u_tab[k];
                    i_sample_i     = i_tab[k];
                    k = k + 1;
                end else begin
                    i_sample_valid = 1'b0;
                end
            end
            @(negedge clk);
            i_sample_valid = 1'b0;
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

        // 等帧结束
        i = 0;
        while (!(frame_done_seen && item_cnt >= ITEMS) && i < 4000000) begin
            @(posedge clk); i = i + 1;
        end
        repeat (10) @(posedge clk);

        $display("");
        $display("========== RFG 缩放级串联（>>%0d 后应直接进 magnitude_calc） ==========", SHIFT);
        $display("输出项数 = %0d（期望 %0d），次序错误 = %0d，末项在 item#%0d，frame_done = %0b",
                 item_cnt, ITEMS, order_err, last_seen_at, frame_done_seen);
        $display("次数 :     u_re    u_im    i_re    i_im");
        for (i = 0; i <= 5; i = i + 1)
            $display("  %0d  : %6d %6d %6d %6d", i, ur[i], ui[i], ir[i], ii[i]);
        $display("  ... 6..64 略");

        if (item_cnt != ITEMS) begin
            $display("FAIL: 输出项数 %0d，期望 %0d", item_cnt, ITEMS);
            errors = errors + 1;
        end
        if (order_err != 0) begin
            $display("FAIL: 次序错误 %0d 次", order_err);
            errors = errors + 1;
        end
        if (last_seen_at != ITEMS - 1) begin
            $display("FAIL: m_bin_last 在 item#%0d，期望 %0d", last_seen_at, ITEMS - 1);
            errors = errors + 1;
        end
        if (!frame_done_seen) begin
            $display("FAIL: o_frame_done 未拉高");
            errors = errors + 1;
        end
        if (fe_channel_error !== 1'b0 || fe_overflow !== 1'b0) begin
            $display("FAIL: channel_error=%0b overflow=%0b", fe_channel_error, fe_overflow);
            errors = errors + 1;
        end

        // 数值（注意算术右移对负数是向下取整）
        check_val(ur[0], 0,   1, "0 次 u_re");
        check_val(ir[0], 0,   1, "0 次 i_re");
        // 改为四舍五入后： (511947+512)>>10=500、(-29+512)>>10=0、(-104+512)>>10=0、(-409632+512)>>10=-400
        check_val(ur[1], 500, 2, "1 次 u_re");
        check_val(ui[1], 0,   2, "1 次 u_im");
        check_val(ir[1], 0,   2, "1 次 i_re");
        check_val(ii[1], -400, 2, "1 次 i_im");
        check_val(ur[3], 200, 2, "3 次 u_re");
        check_val(ui[3], 0,   1, "3 次 u_im");
        for (i = 2; i <= C_K; i = i + 1) begin
            if (i == 3) continue;
            check_val(ur[i], 0, 1, "静默次 u_re");
            check_val(ui[i], 0, 1, "静默次 u_im");
            check_val(ir[i], 0, 1, "静默次 i_re");
            check_val(ii[i], 0, 1, "静默次 i_im");
        end

        if (errors == 0) begin
            $display("");
            $display("PASS: pqm_rfg_scale");
        end else begin
            $display("FAIL: pqm_rfg_scale，共 %0d 处不符", errors);
            $fatal(1, "pqm_rfg_scale 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
