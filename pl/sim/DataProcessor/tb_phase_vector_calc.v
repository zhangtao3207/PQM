`timescale 1ns / 1ps

/*
 * 模块: tb_phase_vector_calc
 * 功能:
 *   phase_vector_calc 的单元测试平台：对 0~500 次谐波统计结果逐项算出
 *   U1-U2 相位差的 atan2 输入向量 dot/cross，并判断该向量是否可用于算相位。
 *
 *   dot   = Ur*Ir + Ui*Ii
 *   cross = Ui*Ir - Ur*Ii
 *   valid = present && (u_mag != 0) && (u2_mag != 0)
 *
 *   六个用例项覆盖：u_mag=0 的旁路、普通同相、负值组合、present=0、
 *   u_mag=0 的大数、以及 16 位边界值（含 33 位宽结果不溢出）。
 *
 *   三个场景：
 *     1) 一整帧 6 项的输出与透传字段核对
 *     2) enable=0 时清空待输出结果
 *     3) 同一帧再来一次，验证可重复
 *
 *   下游 m_harmonic_ready 每收一项空一拍，故意制造反压。
 */

module tb_phase_vector_calc;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底
    localparam integer ITEMS       = 6;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg s_harmonic_valid = 1'b0;
    reg s_harmonic_last = 1'b0;
    reg [8:0] s_harmonic_order = 9'd0;
    reg s_harmonic_present = 1'b0;
    reg signed [15:0] s_u1_real = 16'sd0;
    reg signed [15:0] s_u1_imag = 16'sd0;
    reg signed [15:0] s_u2_real = 16'sd0;
    reg signed [15:0] s_u2_imag = 16'sd0;
    reg [16:0] s_u1_mag = 17'd0;
    reg [16:0] s_u2_mag = 17'd0;
    reg [15:0] s_u1_pct_x100 = 16'd0;
    reg [15:0] s_u2_pct_x100 = 16'd0;
    reg m_harmonic_ready = 1'b0;

    wire               s_harmonic_ready;
    wire               m_harmonic_valid;
    wire               m_harmonic_last;
    wire [8:0]         m_harmonic_order;
    wire               m_harmonic_present;
    wire signed [15:0] m_u1_real;
    wire signed [15:0] m_u1_imag;
    wire signed [15:0] m_u2_real;
    wire signed [15:0] m_u2_imag;
    wire [16:0]        m_u1_mag;
    wire [16:0]        m_u2_mag;
    wire [15:0]        m_u1_pct_x100;
    wire [15:0]        m_u2_pct_x100;
    wire               m_phase_vector_valid;
    wire signed [32:0] m_phase_dot;
    wire signed [32:0] m_phase_cross;

    // 激励与期望值表
    reg        in_present [0:ITEMS-1];
    reg signed [15:0] in_ur [0:ITEMS-1];
    reg signed [15:0] in_ui [0:ITEMS-1];
    reg signed [15:0] in_ir [0:ITEMS-1];
    reg signed [15:0] in_ii [0:ITEMS-1];
    reg [16:0] in_umag [0:ITEMS-1];
    reg [16:0] in_imag [0:ITEMS-1];
    reg [15:0] in_upct [0:ITEMS-1];
    reg [15:0] in_ipct [0:ITEMS-1];

    reg signed [32:0] exp_dot [0:ITEMS-1];
    reg signed [32:0] exp_cross [0:ITEMS-1];
    reg               exp_valid [0:ITEMS-1];

    integer errors = 0;
    integer i;
    integer k;                 // consume_frame 专用下标
    integer m;                 // drive_frame 专用下标：fork 里与 consume_frame 并行，不能共用 k
    integer target;
    integer input_fires = 0;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    phase_vector_calc dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .enable              (enable),
        .s_harmonic_valid    (s_harmonic_valid),
        .s_harmonic_ready    (s_harmonic_ready),
        .s_harmonic_last     (s_harmonic_last),
        .s_harmonic_order    (s_harmonic_order),
        .s_harmonic_present  (s_harmonic_present),
        .s_u1_real            (s_u1_real),
        .s_u1_imag            (s_u1_imag),
        .s_u2_real            (s_u2_real),
        .s_u2_imag            (s_u2_imag),
        .s_u1_mag             (s_u1_mag),
        .s_u2_mag             (s_u2_mag),
        .s_u1_pct_x100        (s_u1_pct_x100),
        .s_u2_pct_x100        (s_u2_pct_x100),
        .m_harmonic_ready    (m_harmonic_ready),
        .m_harmonic_valid    (m_harmonic_valid),
        .m_harmonic_last     (m_harmonic_last),
        .m_harmonic_order    (m_harmonic_order),
        .m_harmonic_present  (m_harmonic_present),
        .m_u1_real            (m_u1_real),
        .m_u1_imag            (m_u1_imag),
        .m_u2_real            (m_u2_real),
        .m_u2_imag            (m_u2_imag),
        .m_u1_mag             (m_u1_mag),
        .m_u2_mag             (m_u2_mag),
        .m_u1_pct_x100        (m_u1_pct_x100),
        .m_u2_pct_x100        (m_u2_pct_x100),
        .m_phase_vector_valid(m_phase_vector_valid),
        .m_phase_dot         (m_phase_dot),
        .m_phase_cross       (m_phase_cross)
    );

    always @(posedge clk) begin
        if (rst_n && s_harmonic_valid && s_harmonic_ready)
            input_fires <= input_fires + 1;
    end

    task init_vectors;
        begin
            // order 0：u_mag=0，被旁路
            in_present[0] = 1'b1;
            in_ur[0] =  16'sd0; in_ui[0] =  16'sd0;
            in_ir[0] =  16'sd0; in_ii[0] =  16'sd0;
            in_umag[0] = 17'd0; in_imag[0] = 17'd10;
            in_upct[0] = 16'd0; in_ipct[0] = 16'd100;
            exp_dot[0] = 33'sd0; exp_cross[0] = 33'sd0; exp_valid[0] = 1'b0;

            // order 1：普通同相，dot=39、cross=2
            in_present[1] = 1'b1;
            in_ur[1] =  16'sd3; in_ui[1] =  16'sd4;
            in_ir[1] =  16'sd5; in_ii[1] =  16'sd6;
            in_umag[1] = 17'd5; in_imag[1] = 17'd7;
            in_upct[1] = 16'd1000; in_ipct[1] = 16'd2000;
            exp_dot[1] = 33'sd39; exp_cross[1] = 33'sd2; exp_valid[1] = 1'b1;

            // order 2：负值组合，dot=-143、cross=2
            in_present[2] = 1'b1;
            in_ur[2] = -16'sd7; in_ui[2] =  16'sd8;
            in_ir[2] =  16'sd9; in_ii[2] = -16'sd10;
            in_umag[2] = 17'd11; in_imag[2] = 17'd13;
            in_upct[2] = 16'd3000; in_ipct[2] = 16'd4000;
            exp_dot[2] = -33'sd143; exp_cross[2] = 33'sd2; exp_valid[2] = 1'b1;

            // order 3：present=0，虽然有值但向量不可用
            in_present[3] = 1'b0;
            in_ur[3] =  16'sd1; in_ui[3] =  16'sd1;
            in_ir[3] =  16'sd1; in_ii[3] =  16'sd1;
            in_umag[3] = 17'd1; in_imag[3] = 17'd1;
            in_upct[3] = 16'd0; in_ipct[3] = 16'd0;
            exp_dot[3] = 33'sd2; exp_cross[3] = 33'sd0; exp_valid[3] = 1'b0;

            // order 4：u_mag=0 的大数项，dot=-110000、cross=20000
            in_present[4] = 1'b1;
            in_ur[4] =  16'sd100;  in_ui[4] = -16'sd200;
            in_ir[4] = -16'sd300;  in_ii[4] =  16'sd400;
            in_umag[4] = 17'd0; in_imag[4] = 17'd5;
            in_upct[4] = 16'd0; in_ipct[4] = 16'd5000;
            exp_dot[4] = -33'sd110000; exp_cross[4] = 33'sd20000; exp_valid[4] = 1'b0;

            // order 5：16 位边界值；u_mag=3、u2_mag=0 -> 向量不可用
            in_present[5] = 1'b1;
            in_ur[5] =  16'sh8000; in_ui[5] =  16'sd32767;
            in_ir[5] =  16'sh8000; in_ii[5] =  16'sh8000;
            in_umag[5] = 17'd3; in_imag[5] = 17'd0;
            in_upct[5] = 16'd6000; in_ipct[5] = 16'd0;
            exp_dot[5]   = 33'sd32768;
            exp_cross[5] = -2147450880;
            exp_valid[5] = 1'b0;
        end
    endtask

    task drive_frame;
        begin
            for (m = 0; m < ITEMS; m = m + 1) begin
                @(negedge clk);
                s_harmonic_order   = m;
                s_harmonic_last    = (m == ITEMS - 1);
                s_harmonic_present = in_present[m];
                s_u1_real           = in_ur[m];
                s_u1_imag           = in_ui[m];
                s_u2_real           = in_ir[m];
                s_u2_imag           = in_ii[m];
                s_u1_mag            = in_umag[m];
                s_u2_mag            = in_imag[m];
                s_u1_pct_x100       = in_upct[m];
                s_u2_pct_x100       = in_ipct[m];
                s_harmonic_valid   = 1'b1;
                target             = input_fires + 1;
                wait (input_fires == target);
            end

            @(negedge clk);
            s_harmonic_valid = 1'b0;
            s_harmonic_last  = 1'b0;
        end
    endtask

    task consume_frame;
        input [127:0] tag;
        begin
            for (k = 0; k < ITEMS; k = k + 1) begin
                ok = 1'b0;
                for (i = 0; i < 200 && !ok; i = i + 1) begin
                    @(negedge clk);
                    if (m_harmonic_valid) ok = 1'b1;
                end

                if (!ok) begin
                    $display("FAIL: %0s 第 %0d 项没有等到 m_harmonic_valid", tag, k);
                    errors = errors + 1;
                end else begin
                    if (m_harmonic_order !== k) begin
                        $display("FAIL: %0s 第 %0d 项 order=%0d 不符", tag, k, m_harmonic_order);
                        errors = errors + 1;
                    end
                    if (m_harmonic_present !== in_present[k]) begin
                        $display("FAIL: %0s order%0d present=%0b，期望 %0b",
                                 tag, k, m_harmonic_present, in_present[k]);
                        errors = errors + 1;
                    end
                    if (m_phase_vector_valid !== exp_valid[k]) begin
                        $display("FAIL: %0s order%0d phase_vector_valid=%0b，期望 %0b",
                                 tag, k, m_phase_vector_valid, exp_valid[k]);
                        errors = errors + 1;
                    end
                    if (m_phase_dot !== exp_dot[k]) begin
                        $display("FAIL: %0s order%0d phase_dot=%0d，期望 %0d",
                                 tag, k, m_phase_dot, exp_dot[k]);
                        errors = errors + 1;
                    end
                    if (m_phase_cross !== exp_cross[k]) begin
                        $display("FAIL: %0s order%0d phase_cross=%0d，期望 %0d",
                                 tag, k, m_phase_cross, exp_cross[k]);
                        errors = errors + 1;
                    end
                    // 透传字段
                    if (m_u1_real !== in_ur[k] || m_u1_imag !== in_ui[k] ||
                        m_u2_real !== in_ir[k] || m_u2_imag !== in_ii[k]) begin
                        $display("FAIL: %0s order%0d 实虚部透传不符", tag, k);
                        errors = errors + 1;
                    end
                    if (m_u1_mag !== in_umag[k] || m_u2_mag !== in_imag[k]) begin
                        $display("FAIL: %0s order%0d 幅值透传不符", tag, k);
                        errors = errors + 1;
                    end
                    if (m_u1_pct_x100 !== in_upct[k] || m_u2_pct_x100 !== in_ipct[k]) begin
                        $display("FAIL: %0s order%0d 百分比透传不符", tag, k);
                        errors = errors + 1;
                    end
                    if (m_harmonic_last !== ((k == ITEMS - 1) ? 1'b1 : 1'b0)) begin
                        $display("FAIL: %0s 第 %0d 项 m_harmonic_last=%0b，期望 %0b",
                                 tag, k, m_harmonic_last, (k == ITEMS - 1));
                        errors = errors + 1;
                    end
                end

                // 取走一项后空一拍 ready，制造反压
                @(negedge clk);
                m_harmonic_ready = 1'b1;
                @(negedge clk);
                m_harmonic_ready = 1'b0;
            end
        end
    endtask

    initial begin
        init_vectors;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // ---------------- 场景 1：第一帧 ----------------
        fork
            drive_frame;
            consume_frame("第一帧");
        join
        repeat (10) @(posedge clk);

        // ---------------- 场景 2：enable=0 时清空 ----------------
        enable = 1'b0;
        repeat (20) @(posedge clk);
        if (m_harmonic_valid !== 1'b0) begin
            $display("FAIL: enable=0 时不应有 m_harmonic_valid");
            errors = errors + 1;
        end
        if (m_phase_vector_valid !== 1'b0) begin
            $display("FAIL: enable=0 时 m_phase_vector_valid 应被清空");
            errors = errors + 1;
        end
        enable = 1'b1;
        repeat (20) @(posedge clk);

        // ---------------- 场景 3：同一帧再来一次 ----------------
        fork
            drive_frame;
            consume_frame("第二帧");
        join
        repeat (10) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: phase_vector_calc");
        end else begin
            $display("FAIL: phase_vector_calc，共 %0d 处不符", errors);
            $fatal(1, "phase_vector_calc 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
