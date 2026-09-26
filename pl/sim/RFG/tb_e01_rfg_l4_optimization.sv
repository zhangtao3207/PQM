`timescale 1ns/1ps

module tb_e01_rfg_l4_optimization #(
    parameter integer C_N = 512,   // PQM2 改动：一帧 = 一个 50 Hz 周期（25.6 kHz 采样）
    parameter integer C_K = 64,    // PQM2 改动：只算前 64 次谐波
    parameter integer C_L = 4,
    parameter integer C_D = 1,
    parameter integer C_RUN_FROZEN = 1,
    // External cycle contract for the L branches that carry no analytic formula
    // in this bench.  Set to -1 to skip; set to a measured value to require
    // exact equality (used for the unified-top L2 equivalence gate).
    parameter integer C_EXPECT_CYCLES = -1
);
    localparam integer C_TIMEOUT_CYCLES = 2000000;
    localparam real C_PI = 3.14159265358979323846;

    reg sys_clk;
    reg rst_n;
    reg i_start;
    reg i_sample_valid;
    reg signed [15:0] i_sample;
    reg i_result_ready;
    wire o_sample_ready;
    wire o_busy;
    wire o_result_valid;
    wire [8:0] o_bin_index;
    wire signed [31:0] o_result_real;
    wire signed [31:0] o_result_imag;
    wire o_result_last;
    wire o_frame_done;
    wire o_overflow;

    integer signed samples [0:C_N-1];
    longint signed expected_real [1:C_K];
    longint signed expected_imag [1:C_K];
    reg [15:0] vector_input [0:C_N-1];
    reg [31:0] vector_expected_real [0:C_K-1];
    reg [31:0] vector_expected_imag [0:C_K-1];
    integer accepted_results;
    integer completed_frames;
    integer error_count;
    integer protocol_error_count;
    integer active_pattern;
    integer ready_lfsr;
    reg enable_backpressure;
    longint cycle_counter;
    longint frame_start_cycle;
    longint last_frame_cycles;
    reg frame_tracking;
    reg require_bit_exact;
    reg previous_stalled;
    reg [8:0] stalled_bin;
    reg signed [31:0] stalled_real;
    reg signed [31:0] stalled_imag;
    integer result_file;

    // Analytic frame-length contract, now valid for every L routed through the
    // shared post-fold engine.  The engine's per-column cost is 10 cycles
    // independent of L, and the phase stage adds 20 cycles (L<=4 skips it).
    //   C_frame = N + ceil(K/D) * (10*(N/L) + (L<=4 ? 21 : 41)) + K
    // Only the asynchronous-read policies are covered: after the atomic
    // refactor every L shares one registered-read fold pipeline (2 cycles per
    // sample), so block mode no longer has a per-L analytic contract.
    function automatic integer expected_direct_cycle_count(
        input integer n_value,
        input integer k_value,
        input integer l_value,
        input integer d_value
    );
        integer batch_count;
        integer fixed_batch_cycles;
        begin
            batch_count = (k_value+d_value-1)/d_value;
            fixed_batch_cycles = (l_value <= 4) ? 21 : 41;
            expected_direct_cycle_count = n_value+
                batch_count*(10*(n_value/l_value)+fixed_batch_cycles)+k_value;
        end
    endfunction

`ifdef E01_RFG_UNIFIED
    // Atomic-model path: one top, C_L is a compile-time parameter.  Implicit
    // port connection is safe because every DUT net name matches this bench.
    e01_rfg_nkld_top #(
        .C_N(C_N),
        .C_K(C_K),
        .C_L(C_L),
        .C_D(C_D)
    ) u_dut (.*);
`else
`ifdef E01_RFG_L2
    e01_rfg_l2_top #(
`elsif E01_RFG_L8
    e01_rfg_l8_top #(
`elsif E01_RFG_L16
    e01_rfg_l16_top #(
`else
    e01_rfg_l4_top #(
`endif
        .C_N(C_N),
        .C_K(C_K),
        .C_D(C_D)
    ) u_dut (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_sample_valid(i_sample_valid),
        .i_sample(i_sample),
        .i_result_ready(i_result_ready),
        .o_sample_ready(o_sample_ready),
        .o_busy(o_busy),
        .o_result_valid(o_result_valid),
        .o_bin_index(o_bin_index),
        .o_result_real(o_result_real),
        .o_result_imag(o_result_imag),
        .o_result_last(o_result_last),
        .o_frame_done(o_frame_done),
        .o_overflow(o_overflow)
    );
`endif

    always #10 sys_clk = ~sys_clk;

    function automatic integer signed round_real(input real value);
        begin
            if (value >= 0.0)
                round_real = $rtoi(value+0.5);
            else
                round_real = $rtoi(value-0.5);
        end
    endfunction

    function automatic longint signed absolute_long(input longint signed value);
        begin
            absolute_long = (value < 0) ? -value : value;
        end
    endfunction

    task automatic prepare_pattern(input integer pattern);
        integer n;
        integer k;
        real value;
        real real_sum;
        real imag_sum;
        real angle;
        begin
            for (n = 0; n < C_N; n = n+1) begin
                case (pattern)
                    0: samples[n] = 0;
                    1: samples[n] = (n == 0) ? 8192 : 0;
                    2: begin
                        value = 0.32*$cos(2.0*C_PI*3.0*n/C_N) +
                                0.21*$sin(2.0*C_PI*7.0*n/C_N) +
                                0.07*$cos(2.0*C_PI*11.0*n/C_N);
                        samples[n] = round_real(value*16384.0);
                    end
                    default: samples[n] = ((n*977 + pattern*131) % 30001)-15000;
                endcase
            end

            for (k = 1; k <= C_K; k = k+1) begin
                real_sum = 0.0;
                imag_sum = 0.0;
                for (n = 0; n < C_N; n = n+1) begin
                    angle = 2.0*C_PI*k*n/C_N;
                    real_sum = real_sum + 2.0*samples[n]*$cos(angle);
                    imag_sum = imag_sum - 2.0*samples[n]*$sin(angle);
                end
                expected_real[k] = round_real(real_sum);
                expected_imag[k] = round_real(imag_sum);
            end
            compute_common_reference();
        end
    endtask

    task automatic apply_reset;
        begin
            @(negedge sys_clk);
            rst_n = 1'b0;
            i_start = 1'b0;
            i_sample_valid = 1'b0;
            i_sample = 16'sd0;
            repeat (3) @(negedge sys_clk);
            rst_n = 1'b1;
            repeat (2) @(negedge sys_clk);
            if (o_busy || o_result_valid) begin
                $error("Reset did not return the core to idle");
                error_count = error_count+1;
                protocol_error_count = protocol_error_count+1;
            end
        end
    endtask

    task automatic start_frame;
        begin
            @(negedge sys_clk);
            i_start = 1'b1;
            @(negedge sys_clk);
            i_start = 1'b0;
            while (!o_sample_ready) @(negedge sys_clk);
        end
    endtask

    task automatic drive_samples(input integer inject_gaps, input integer repeat_start);
        integer n;
        integer gap_counter;
        begin
            n = 0;
            gap_counter = 0;
            while (n < C_N) begin
                @(negedge sys_clk);
                if (repeat_start && n == (C_N/3))
                    i_start = 1'b1;
                else
                    i_start = 1'b0;
                if (o_sample_ready && (!inject_gaps || ((n+gap_counter) % 4 != 1))) begin
                    i_sample_valid = 1'b1;
                    i_sample = samples[n][15:0];
                    n = n+1;
                end else begin
                    i_sample_valid = 1'b0;
                    i_sample = 16'sd0;
                    gap_counter = gap_counter+1;
                end
            end
            @(negedge sys_clk);
            i_start = 1'b0;
            i_sample_valid = 1'b0;
            i_sample = 16'sd0;
        end
    endtask

    task automatic wait_for_frame(input integer expected_frame_number);
        integer cycles;
        begin
            cycles = 0;
            while (completed_frames < expected_frame_number && cycles < C_TIMEOUT_CYCLES) begin
                @(posedge sys_clk);
                cycles = cycles+1;
            end
            if (completed_frames < expected_frame_number) begin
                $error("Frame timeout pattern=%0d N=%0d K=%0d L=%0d D=%0d",
                       active_pattern,C_N,C_K,C_L,C_D);
                error_count = error_count+1;
                protocol_error_count = protocol_error_count+1;
            end
        end
    endtask

    task automatic run_frame(input integer pattern, input integer inject_gaps);
        integer target_frame;
        integer errors_before;
        integer expected_cycles;
        begin
            active_pattern = pattern;
            require_bit_exact = 1'b0;
            errors_before = error_count;
            enable_backpressure = (pattern != 0);
            prepare_pattern(pattern);
            accepted_results = 0;
            previous_stalled = 1'b0;
            target_frame = completed_frames+1;
            start_frame();
            drive_samples(inject_gaps,1);
            wait_for_frame(target_frame);
            expected_cycles = expected_direct_cycle_count(C_N,C_K,C_L,C_D);
            if (expected_cycles < 0) expected_cycles = C_EXPECT_CYCLES;
            if (pattern == 0 && expected_cycles >= 0) begin
                if (last_frame_cycles != expected_cycles) begin
                    $error("Direct-L cycle contract failed N=%0d K=%0d L=%0d D=%0d got=%0d expected=%0d",
                           C_N,C_K,C_L,C_D,last_frame_cycles,expected_cycles);
                    error_count = error_count+1;
                end else begin
                    $display("E01_RFG_DIRECT_L_CYCLE_PASS N=%0d K=%0d L=%0d D=%0d cycles=%0d",
                             C_N,C_K,C_L,C_D,last_frame_cycles);
                end
            end
            if (accepted_results != C_K) begin
                $error("Result count mismatch pattern=%0d got=%0d expected=%0d",
                       pattern,accepted_results,C_K);
                error_count = error_count+1;
                protocol_error_count = protocol_error_count+1;
            end
            if (error_count == errors_before)
                $display("E01_RFG_CASE_PASS pattern=%0d N=%0d K=%0d L=%0d D=%0d overflow=%0d",
                         pattern,C_N,C_K,C_L,C_D,o_overflow);
            else
                $display("E01_RFG_CASE_FAIL pattern=%0d N=%0d K=%0d L=%0d D=%0d",
                         pattern,C_N,C_K,C_L,C_D);
            $display("E01_RFG_FRAME_CYCLES pattern=%0d cycles=%0d",pattern,last_frame_cycles);
            report_common_case($sformatf("pattern%0d", pattern));
        end
    endtask

    task automatic run_matlab_vector(input integer vector_index);
        integer n;
        integer k;
        integer target_frame;
        integer errors_before;
        begin
            case (vector_index)
                0: begin
                    $readmemh("input_zero_q14.hex",vector_input);
                    $readmemh("expected_zero_real_q15.hex",vector_expected_real);
                    $readmemh("expected_zero_imag_q15.hex",vector_expected_imag);
                end
                1: begin
                    $readmemh("input_impulse_q14.hex",vector_input);
                    $readmemh("expected_impulse_real_q15.hex",vector_expected_real);
                    $readmemh("expected_impulse_imag_q15.hex",vector_expected_imag);
                end
                2: begin
                    $readmemh("input_tone_k1_q14.hex",vector_input);
                    $readmemh("expected_tone_k1_real_q15.hex",vector_expected_real);
                    $readmemh("expected_tone_k1_imag_q15.hex",vector_expected_imag);
                end
                3: begin
                    $readmemh("input_tone_edge_q14.hex",vector_input);
                    $readmemh("expected_tone_edge_real_q15.hex",vector_expected_real);
                    $readmemh("expected_tone_edge_imag_q15.hex",vector_expected_imag);
                end
                default: begin
                    $readmemh("input_multi_harmonic_q14.hex",vector_input);
                    $readmemh("expected_multi_harmonic_real_q15.hex",vector_expected_real);
                    $readmemh("expected_multi_harmonic_imag_q15.hex",vector_expected_imag);
                end
            endcase
            for (n=0; n<C_N; n=n+1) samples[n] = $signed(vector_input[n]);
            compute_common_reference();
            for (k=1; k<=C_K; k=k+1) begin
                expected_real[k] = $signed(vector_expected_real[k-1]);
                expected_imag[k] = $signed(vector_expected_imag[k-1]);
            end
            active_pattern = 10+vector_index;
            errors_before = error_count;
            require_bit_exact = 1'b1;
            enable_backpressure = (vector_index != 0);
            accepted_results = 0;
            previous_stalled = 1'b0;
            target_frame = completed_frames+1;
            start_frame();
            drive_samples(vector_index != 0,1);
            wait_for_frame(target_frame);
            if (accepted_results != C_K) begin
                $error("Frozen vector result count mismatch vector=%0d got=%0d expected=%0d",
                       vector_index,accepted_results,C_K);
                error_count = error_count+1;
                protocol_error_count = protocol_error_count+1;
            end
            if (error_count == errors_before)
                $display("E01_RFG_FROZEN_VECTOR_PASS vector=%0d N=%0d K=%0d L=%0d D=%0d cycles=%0d",
                         vector_index,C_N,C_K,C_L,C_D,last_frame_cycles);
            else
                $display("E01_RFG_FROZEN_VECTOR_FAIL vector=%0d N=%0d K=%0d L=%0d D=%0d",
                         vector_index,C_N,C_K,C_L,C_D);
            report_common_case($sformatf("vector%0d", vector_index));
        end
    endtask

    always @(negedge sys_clk) begin
        if (!rst_n) begin
            i_result_ready <= 1'b0;
            ready_lfsr <= 32'h13579bdf;
        end else if (!enable_backpressure) begin
            i_result_ready <= 1'b1;
        end else begin
            ready_lfsr <= {ready_lfsr[30:0],ready_lfsr[31]^ready_lfsr[21]^ready_lfsr[1]^ready_lfsr[0]};
            i_result_ready <= ready_lfsr[0] | ready_lfsr[3];
        end
    end

    longint signed observed_real;
    // ---- 共同口径证据（2026-09-15 新增；additive，既有变量一个都不复用）----
    // 共同参考 = TB 内双精度 DFT（与既有 prepare_pattern 同公式、同因子 2），与各家冻结 golden
    // 分开存放；门限沿用既有 RFG 容差 C_N + |ref|/1000。精度只报告、不 $fatal，
    // 「预期无溢出」用例的 overflow 则按既有失败机制计入 error_count。
    longint signed cr_ref_real [1:C_K];
    longint signed cr_ref_imag [1:C_K];
    longint signed cr_err [1:C_K];
    longint signed cr_tol [1:C_K];
    longint signed cr_max_err;
    longint signed cr_max_tol;
    longint signed cr_best_err;
    longint signed cr_best_tol;
    longint signed cr_cand_err;
    longint signed cr_cand_tol;
    longint signed cr_ratio_milli;
    longint signed cr_tmp;
    integer cr_worst_bin;
    integer cr_fail_count;
    integer cr_bin;
    integer cr_n;
    real cr_acc_real;
    real cr_acc_imag;
    real cr_angle;
    longint cr_start_cycle;
    longint cr_last_result_cycle;
    logic cr_ov_seen;
    logic cr_ov_live;

    task automatic compute_common_reference;
        begin
            for (cr_bin = 1; cr_bin <= C_K; cr_bin = cr_bin+1) begin
                cr_acc_real = 0.0;
                cr_acc_imag = 0.0;
                for (cr_n = 0; cr_n < C_N; cr_n = cr_n+1) begin
                    cr_angle = 2.0*C_PI*cr_bin*cr_n/C_N;
                    cr_acc_real = cr_acc_real + 2.0*samples[cr_n]*$cos(cr_angle);
                    cr_acc_imag = cr_acc_imag - 2.0*samples[cr_n]*$sin(cr_angle);
                end
                cr_ref_real[cr_bin] = round_real(cr_acc_real);
                cr_ref_imag[cr_bin] = round_real(cr_acc_imag);
                cr_tol[cr_bin] = C_N + ((absolute_long(cr_ref_real[cr_bin]) > absolute_long(cr_ref_imag[cr_bin]))
                    ? absolute_long(cr_ref_real[cr_bin]) : absolute_long(cr_ref_imag[cr_bin]))/1000;
                cr_err[cr_bin] = 0;
            end
        end
    endtask

    task automatic report_common_case(input string case_name);
        begin
            cr_max_err = 0;
            cr_max_tol = 0;
            cr_fail_count = 0;
            cr_worst_bin = 1;
            cr_best_err = -1;
            cr_best_tol = 1;
            for (cr_bin = 1; cr_bin <= C_K; cr_bin = cr_bin+1) begin
                if (cr_err[cr_bin] > cr_max_err) cr_max_err = cr_err[cr_bin];
                if (cr_tol[cr_bin] > cr_max_tol) cr_max_tol = cr_tol[cr_bin];
                if (cr_err[cr_bin] > cr_tol[cr_bin]) cr_fail_count = cr_fail_count+1;
                cr_cand_err = cr_err[cr_bin];
                cr_cand_tol = cr_tol[cr_bin];
                if ((cr_best_err*cr_cand_tol) < (cr_cand_err*cr_best_tol)) begin
                    cr_best_err = cr_cand_err;
                    cr_best_tol = cr_cand_tol;
                    cr_worst_bin = cr_bin;
                end
            end
            cr_ratio_milli = ((1000*cr_best_err)+cr_best_tol-1)/cr_best_tol;
            $display("E01_COMMON_ACCURACY_RFG case=%s n=%0d k=%0d l=%0d d=%0d max_err=%0d max_tol=%0d worst_bin=%0d ratio_milli=%0d verdict=%s",
                case_name, C_N, C_K, C_L, C_D, cr_max_err, cr_max_tol, cr_worst_bin,
                cr_ratio_milli, (cr_fail_count == 0) ? "PASS" : "FAIL");
            if (cr_fail_count != 0)
                for (cr_bin = 1; cr_bin <= C_K; cr_bin = cr_bin+1)
                    if (cr_err[cr_bin] > cr_tol[cr_bin])
                        $display("E01_COMMON_ACCURACY_RFG_EXCEED case=%s bin=%0d err=%0d tol=%0d",
                            case_name, cr_bin, cr_err[cr_bin], cr_tol[cr_bin]);
            if (cr_ov_seen === 1'b1) begin
                $display("E01_OVERFLOW_UNEXPECTED RFG case=%s", case_name);
                error_count = error_count+1;
            end
            $display("E01_FRAME_EVENTS RFG n=%0d k=%0d l=%0d d=%0d start=%0d first_sample=%0d last_result=%0d reported=%0d start_based=%0d sample_based=%0d",
                C_N, C_K, C_L, C_D, cr_start_cycle, frame_start_cycle, cr_last_result_cycle,
                last_frame_cycles, cr_last_result_cycle-cr_start_cycle+1,
                cr_last_result_cycle-frame_start_cycle+1);
        end
    endtask
    longint signed observed_imag;
    longint signed real_error;
    longint signed imag_error;
    longint signed real_tolerance;
    longint signed imag_tolerance;
    always @(posedge sys_clk) begin
        if (!rst_n) begin
            previous_stalled <= 1'b0;
            frame_tracking <= 1'b0;
        end else begin
            cycle_counter = cycle_counter+1;
            if (i_sample_valid && o_sample_ready && !frame_tracking) begin
                frame_start_cycle = cycle_counter;
                frame_tracking = 1'b1;
            end
            // 共同口径：start 事件拍与帧内 overflow 观察（additive）
            if (i_start && !o_busy) begin
                cr_start_cycle = cycle_counter;
                cr_ov_seen = 1'b0;
                cr_ov_live = 1'b1;
            end else if (cr_ov_live && o_overflow === 1'b1) begin
                cr_ov_seen = 1'b1;
            end
            if (previous_stalled) begin
                if (!o_result_valid || o_bin_index != stalled_bin ||
                    o_result_real != stalled_real || o_result_imag != stalled_imag) begin
                    $error("Result changed while backpressured");
                    error_count = error_count+1;
                    protocol_error_count = protocol_error_count+1;
                end
            end
            previous_stalled <= o_result_valid && !i_result_ready;
            if (o_result_valid && !i_result_ready) begin
                stalled_bin <= o_bin_index;
                stalled_real <= o_result_real;
                stalled_imag <= o_result_imag;
            end
            if (o_result_valid && i_result_ready) begin
                if (o_bin_index != accepted_results+1) begin
                    $error("Bin order mismatch got=%0d expected=%0d",o_bin_index,accepted_results+1);
                    error_count = error_count+1;
                    protocol_error_count = protocol_error_count+1;
                end
                observed_real = $signed(o_result_real);
                observed_imag = $signed(o_result_imag);
                // 共同口径：与 TB 双精度参考的误差（只报告，不改既有判据）
                cr_tmp = absolute_long(observed_real-cr_ref_real[o_bin_index]);
                if (cr_tmp > cr_err[o_bin_index]) cr_err[o_bin_index] = cr_tmp;
                cr_tmp = absolute_long(observed_imag-cr_ref_imag[o_bin_index]);
                if (cr_tmp > cr_err[o_bin_index]) cr_err[o_bin_index] = cr_tmp;
                $fdisplay(result_file,"%0d,%0d,%0d,%0d",
                          active_pattern,o_bin_index,observed_real,observed_imag);
                real_error = absolute_long(observed_real-expected_real[o_bin_index]);
                imag_error = absolute_long(observed_imag-expected_imag[o_bin_index]);
                real_tolerance = require_bit_exact ? 0 :
                    C_N + absolute_long(expected_real[o_bin_index])/1000;
                imag_tolerance = require_bit_exact ? 0 :
                    C_N + absolute_long(expected_imag[o_bin_index])/1000;
                if (real_error > real_tolerance || imag_error > imag_tolerance) begin
                    $error("Numeric mismatch pattern=%0d bin=%0d got=(%0d,%0d) expected=(%0d,%0d) error=(%0d,%0d) tolerance=(%0d,%0d)",
                           active_pattern,o_bin_index,observed_real,observed_imag,
                           expected_real[o_bin_index],expected_imag[o_bin_index],
                           real_error,imag_error,real_tolerance,imag_tolerance);
                    error_count = error_count+1;
                end
                accepted_results = accepted_results+1;
                if (o_result_last != (o_bin_index == C_K)) begin
                    $error("result_last mismatch at bin %0d",o_bin_index);
                    error_count = error_count+1;
                    protocol_error_count = protocol_error_count+1;
                end
            end
            if (o_frame_done) begin
                last_frame_cycles = cycle_counter-frame_start_cycle+1;
                cr_last_result_cycle = cycle_counter;
                cr_ov_live = 1'b0;
                frame_tracking = 1'b0;
                completed_frames = completed_frames+1;
            end
        end
    end

    integer aborted_sample;
    initial begin
        sys_clk = 1'b0;
        rst_n = 1'b0;
        i_start = 1'b0;
        i_sample_valid = 1'b0;
        i_sample = 16'sd0;
        i_result_ready = 1'b0;
        ready_lfsr = 32'h13579bdf;
        accepted_results = 0;
        completed_frames = 0;
        error_count = 0;
        protocol_error_count = 0;
        active_pattern = -1;
        previous_stalled = 1'b0;
        result_file = $fopen("rfg_results.csv","w");
        if (result_file == 0) $fatal(1,"Cannot create rfg_results.csv");
        $fdisplay(result_file,"pattern,bin,real,imag");
        cycle_counter = 0;
        frame_start_cycle = 0;
        last_frame_cycles = 0;
        frame_tracking = 1'b0;
        require_bit_exact = 1'b0;
        enable_backpressure = 1'b0;

        apply_reset();

        // Reset during an interrupted input frame.
        prepare_pattern(1);
        start_frame();
        for (aborted_sample = 0; aborted_sample < 7; aborted_sample = aborted_sample+1) begin
            @(negedge sys_clk);
            i_sample_valid = 1'b1;
            i_sample = samples[aborted_sample][15:0];
        end
        apply_reset();

        run_frame(0,0);
        run_frame(1,1);
        run_frame(2,1);
        run_frame(3,1);
        if (C_RUN_FROZEN != 0) begin
            run_matlab_vector(0);
            run_matlab_vector(1);
            run_matlab_vector(2);
            run_matlab_vector(3);
            run_matlab_vector(4);
        end else begin
            $display("E01_RFG_FROZEN_VECTOR_SKIPPED N=%0d K=%0d L=%0d D=%0d",
                     C_N,C_K,C_L,C_D);
        end

        if (protocol_error_count == 0)
            $display("E01_RFG_PROTOCOL_ALL_PASS N=%0d K=%0d L=%0d D=%0d",C_N,C_K,C_L,C_D);
        else
            $display("E01_RFG_PROTOCOL_FAIL N=%0d K=%0d L=%0d D=%0d errors=%0d",
                     C_N,C_K,C_L,C_D,protocol_error_count);
        if (error_count == 0) begin
            $fclose(result_file);
            $display("E01_RFG_ALL_CASES_PASS N=%0d K=%0d L=%0d D=%0d",C_N,C_K,C_L,C_D);
            // PQM2 改动：run_xsim.ps1 的判定口径要求打印 "PASS: <用例名>"
            $display("PASS: e01_rfg_l4_optimization");
            $finish;
        end
        $fclose(result_file);
        $fatal(1,"E01 RFG test failed with %0d errors",error_count);
    end
endmodule
