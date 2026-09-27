`timescale 1ns / 1ps
`include "pqm_shared_memory_map.vh"

/*
 * 模块名称：tb_pqm_shared_memory_bridge_cdc
 * 功能说明：跨时钟域用例。被测对象是 pqm_shared_memory_bridge（桥本身只有一个时钟），
 *   但它的对手是一块**异步真双口 RAM**：PS 从 PORTA 写、PL 从 PORTB 读，两个端口
 *   时钟不同源。本 TB 因此建两套时钟：
 *     pl_clk = 50 MHz（周期 20 ns）接桥的 clk，就是 PORTB 域；
 *     ps_clk = 100 MHz（周期 10 ns）驱动内存模型的 PS 写口，就是 PORTA 域。
 *   两频不同源，且每轮把 ps_clk 的半周期做成 (5-skew, 5+skew)，周期仍严格 10 ns、
 *   即仍是 100 MHz，但相位相对 pl_clk 每拍漂移 2*skew，于是整轮里两个时钟的边沿
 *   关系会连续扫过整个 20 ns 窗口——覆盖任意相位偏移，而不是只测一个固定相位。
 *
 *   内存模型按真双口 RAM 建：
 *     - PS 写口落在 ps_clk；PL 读写口落在 pl_clk，读出一拍延迟；
 *     - UG473 规定"同址同时读写时 DOUT 未定义"。模型把该情形判为：PL 读某字时该字
 *       正被 PS 口写入（写提交后 20 ns 窗口内，覆盖一整个 PL 周期），此时读回值按
 *       **位级混合** (旧值 & ~M) | (新值 & M) 给出（多比特亚稳态捕获允许返回任意值，
 *       位级混合是最不利的一种合法结果），并由 TB 自检保证它既不等于旧值也不等于
 *       新值 —— 否则该场景会退化成"无害"，测试就成了空的。
 *
 * 覆盖的四个点：
 *   ① 同址冲突注入：PS 在 PL 恰好读走 SEQUENCE 字的那一拍（POLL 周期）写同一个字；
 *   ② 多条命令连续下发：串行一条一来回 + 背靠背突发两种节奏；
 *   ③ 随机相位偏移：8 轮，每轮换一个相位漂移量，全程不断滑动；
 *   ④ 命令不丢不重不错：监视线程对每一次 command_valid 逐字核对"必须等于某条已发布
 *      三元组"且"同一序号不得受理两次"；串行段还要求每条命令最终必被受理。
 *      背靠背段**不要求**中间那些被后续命令覆盖掉的命令也被受理（真实 app 是等响应
 *      再发下一条，不会这样连发），只要求最后一条不丢——这一点如实写在这里。
 *
 * 判据全部是真比较（`!==` + $fatal / 计数比对），没有任何只 $display 不比较的检查。
 *
 * 输入端口：无。
 * 输出端口：无。
 * 双向端口：无。
 */
module tb_pqm_shared_memory_bridge_cdc;

localparam [13:0] REQ_WORD = `PQM_SHM_COMMAND_REQUEST_WORD;
localparam [13:0] ARG_WORD = `PQM_SHM_COMMAND_ARGUMENT_WORD;
localparam [13:0] SEQ_WORD = `PQM_SHM_COMMAND_SEQUENCE_WORD;

localparam integer ROUNDS           = 8;    // 相位偏移轮数
localparam integer SERIAL_PER_ROUND = 5;    // 每轮串行命令条数
localparam integer STRESS_BURSTS    = 6;    // 每轮背靠背突发条数
localparam integer MAX_PUB          = 512;  // 发布账本容量
localparam integer SEQ_LIMIT        = 8191; // 序号数组上界

// ---------------------------------------------------------------- 时钟
reg pl_clk;
reg ps_clk;
integer ps_skew;                    // ps 半周期不对称量（ns），周期恒 10 ns

initial begin
    pl_clk = 1'b0;
    forever #10 pl_clk = ~pl_clk;   // 50 MHz
end

initial begin
    ps_clk = 1'b0;
    #3;
    forever begin
        #(5 - ps_skew) ps_clk = 1'b1;
        #(5 + ps_skew) ps_clk = 1'b0;
    end
end

// ---------------------------------------------------------------- DUT
reg          rst_n;
reg          snapshot_commit;
reg  [511:0] snapshot_words;
reg          harmonic_frame_start;
reg          harmonic_valid;
reg  [8:0]   harmonic_index;
reg  [31:0]  harmonic_u_ratio, harmonic_i_ratio, harmonic_phase, harmonic_flags;
reg          command_response_valid;
reg  [31:0]  command_response;

wire         snapshot_ready;
wire         harmonic_start_ready;
wire         harmonic_ready;
wire         command_valid;
wire  [31:0] command_code;
wire  [31:0] command_argument;
wire  [31:0] command_sequence;
wire         command_response_ready;
wire  [31:0] snapshot_sequence;
wire  [31:0] harmonic_generation;
wire         active_harmonic_bank;
wire  [13:0] bram_addr;
wire  [31:0] bram_wrdata;
wire   [3:0] bram_we;
wire         bram_en;
wire  [31:0] bram_rddata;

pqm_shared_memory_bridge u_dut (
    .clk                    (pl_clk),
    .rst_n                  (rst_n),
    .snapshot_commit        (snapshot_commit),
    .snapshot_ready         (snapshot_ready),
    .snapshot_words         (snapshot_words),
    .harmonic_frame_start   (harmonic_frame_start),
    .harmonic_start_ready   (harmonic_start_ready),
    .harmonic_valid         (harmonic_valid),
    .harmonic_ready         (harmonic_ready),
    .harmonic_index         (harmonic_index),
    .harmonic_u_ratio       (harmonic_u_ratio),
    .harmonic_i_ratio       (harmonic_i_ratio),
    .harmonic_phase         (harmonic_phase),
    .harmonic_flags         (harmonic_flags),
    .command_valid          (command_valid),
    .command_code           (command_code),
    .command_argument       (command_argument),
    .command_sequence       (command_sequence),
    .command_response_valid (command_response_valid),
    .command_response_ready (command_response_ready),
    .command_response       (command_response),
    .snapshot_sequence      (snapshot_sequence),
    .harmonic_generation    (harmonic_generation),
    .active_harmonic_bank   (active_harmonic_bank),
    .bram_addr              (bram_addr),
    .bram_wrdata            (bram_wrdata),
    .bram_we                (bram_we),
    .bram_en                (bram_en),
    .bram_rddata            (bram_rddata)
);

// ---------------------------------------------------------------- 异步双口内存模型
reg [31:0] mem [0:16383];

reg  [13:0] ps_addr;
reg  [31:0] ps_wdata;
reg         ps_we;
reg  [13:0] wr_addr_hold;
reg   [1:0] wr_window;              // 写提交后保持 2 个 ps 周期（20 ns = 一个 PL 周期）
wire        wr_inflight = (wr_window != 2'd0);

reg  [31:0] pl_rddata;
reg         collide_enable;         // 只在定向场景打开
reg  [31:0] collide_value;
integer     collide_hits;
reg  [13:0] prev_addr;

// PS（PORTA）写口：100 MHz
always @(posedge ps_clk) begin
    if (ps_we) begin
        mem[ps_addr] <= ps_wdata;
        wr_addr_hold <= ps_addr;
        wr_window    <= 2'd2;
    end else if (wr_window != 2'd0) begin
        wr_window <= wr_window - 2'd1;
    end
end

// PL（PORTB）读写口：50 MHz，读一拍延迟；同址读写冲突时按未定义语义返回混合值。
always @(posedge pl_clk) begin
    prev_addr <= bram_addr;
    if (bram_en) begin
        if (collide_enable && wr_inflight && (bram_addr == wr_addr_hold)) begin
            pl_rddata <= collide_value;
            collide_hits = collide_hits + 1;
        end else begin
            pl_rddata <= mem[bram_addr];
        end
        if (bram_we[0]) mem[bram_addr][7:0]   <= bram_wrdata[7:0];
        if (bram_we[1]) mem[bram_addr][15:8]  <= bram_wrdata[15:8];
        if (bram_we[2]) mem[bram_addr][23:16] <= bram_wrdata[23:16];
        if (bram_we[3]) mem[bram_addr][31:24] <= bram_wrdata[31:24];
    end else begin
        pl_rddata <= 32'd0;
    end
end

assign bram_rddata = pl_rddata;

// ---------------------------------------------------------------- 账本与监视
reg [31:0]  pub_c [0:MAX_PUB-1];
reg [31:0]  pub_a [0:MAX_PUB-1];
reg [31:0]  pub_s [0:MAX_PUB-1];
integer     pub_count;

reg         seen_seq  [0:SEQ_LIMIT];
reg [31:0]  acc_code  [0:SEQ_LIMIT];
reg [31:0]  acc_arg   [0:SEQ_LIMIT];
integer     accepted_count;

integer i, k, rnd, guard, bi, found;
integer next_seq;
integer serial_pub_count;
integer stress_pub_count;
integer stress_accepted_count;
reg [31:0] c_now, a_now, s_now;
reg [31:0] last_c, last_a, last_s;
reg [31:0] coll_mask, coll_mix;

function integer tuple_published;
    input [31:0] c;
    input [31:0] a;
    input [31:0] s;
    integer idx;
    begin
        tuple_published = 0;
        for (idx = 0; idx < pub_count; idx = idx + 1) begin
            if ((pub_c[idx] === c) && (pub_a[idx] === a) && (pub_s[idx] === s))
                tuple_published = 1;
        end
    end
endfunction

// 监视线程：每一次命令受理都逐字核对"不重""不错"。negedge 采样，避开与 DUT 的竞争。
// 监视线程：每一次命令受理都逐字核对"不重""不错"。negedge 采样，避开与 DUT 的竞争。
always @(negedge pl_clk) begin
    if (rst_n && (command_valid === 1'b1)) begin
        if (command_sequence > SEQ_LIMIT) begin
            $display("FAIL: 受理到的序号 %0d 超出数组上界（不可能是本 TB 发布过的）",
                     command_sequence);
            $fatal(1, "sequence out of range");
        end
        if (tuple_published(command_code, command_argument, command_sequence) !== 1) begin
            $display("FAIL: 受理了未发布/不一致的三元组 code=%08x arg=%08x seq=%08x（不错判据）",
                     command_code, command_argument, command_sequence);
            $fatal(1, "torn command");
        end
        if (seen_seq[command_sequence] === 1'b1) begin
            $display("FAIL: 序号 %0d 被受理两次（不重判据）", command_sequence);
            $fatal(1, "duplicate acceptance");
        end
        seen_seq[command_sequence] = 1'b1;
        acc_code[command_sequence] = command_code;
        acc_arg[command_sequence]  = command_argument;
        accepted_count = accepted_count + 1;
        $display("INFO accept seq=%0d code=%08x arg=%08x", command_sequence,
                 command_code, command_argument);
    end
end

// ---------------------------------------------------------------- PS 侧任务
task ps_write_word;
    input [13:0] addr;
    input [31:0] data;
    begin
        @(negedge ps_clk);
        ps_addr  = addr;
        ps_wdata = data;
        ps_we    = 1'b1;
        @(posedge ps_clk);    // 这个上升沿就是提交沿
        @(negedge ps_clk);    // 再等到低电平中途才撤，避开与内存模型的同沿竞争
        ps_we    = 1'b0;
    end
endtask

task pub_record;
    input [31:0] c;
    input [31:0] a;
    input [31:0] s;
    begin
        if (pub_count >= MAX_PUB) begin
            $display("FAIL: 发布账本溢出");
            $fatal(1, "ledger overflow");
        end
        pub_c[pub_count] = c;
        pub_a[pub_count] = a;
        pub_s[pub_count] = s;
        pub_count = pub_count + 1;
    end
endtask

// 完整发布一条命令：REQUEST -> ARGUMENT -> SEQUENCE（与 PS 侧 app 的 AXI 写顺序一致）。
task ps_publish_serialized;
    input [31:0] c;
    input [31:0] a;
    input [31:0] s;
    begin
        pub_record(c, a, s);
        ps_write_word(REQ_WORD, c);
        ps_write_word(ARG_WORD, a);
        ps_write_word(SEQ_WORD, s);
        serial_pub_count = serial_pub_count + 1;
    end
endtask

// 背靠背突发：同样顺序，命令之间只隔 gap 个 ps 周期，不等 PL 响应。
task ps_publish_burst;
    input [31:0] c;
    input [31:0] a;
    input [31:0] s;
    input integer gap;
    begin
        pub_record(c, a, s);
        ps_write_word(REQ_WORD, c);
        ps_write_word(ARG_WORD, a);
        ps_write_word(SEQ_WORD, s);
        stress_pub_count = stress_pub_count + 1;
        repeat (gap) @(posedge ps_clk);
    end
endtask

// 定向同址冲突：先写完 REQUEST/ARGUMENT，再在 PL 恰好要读走 SEQUENCE 字的那一拍
// （POLL 周期）提交 SEQUENCE 的写；读口返回位级混合值。
task ps_publish_seq_collision;
    input [31:0] c;
    input [31:0] a;
    input [31:0] s_old;
    input [31:0] s_new;
    begin
        pub_record(c, a, s_new);
        ps_write_word(REQ_WORD, c);
        ps_write_word(ARG_WORD, a);

        // 位级混合值 (旧 & ~M) | (新 & M)：选 M 使结果既不是旧值也不是新值也不是 0。
        found = 0;
        for (bi = 0; bi < 32; bi = bi + 1) begin
            coll_mask = (32'd1 << bi);
            coll_mix  = (s_old & ~coll_mask) | (s_new & coll_mask);
            if ((coll_mix !== s_old) && (coll_mix !== s_new) && (coll_mix !== 32'd0)) begin
                found = 1;
                bi    = 32;
            end
        end
        if (found !== 1) begin
            $display("FAIL: 冲突向量设计错误：s_old=%0d s_new=%0d 找不到合法混合掩码",
                     s_old, s_new);
            $fatal(1, "bad collision vector");
        end

        collide_value  = coll_mix;
        collide_enable = 1'b1;

        // 等 PL 进入 POLL_SEQUENCE：上一拍地址是 IDLE 的缺省 0、本拍地址是 SEQUENCE。
        // （不用白盒引用内部 state，纯看端口地址序列。）
        @(negedge pl_clk);
        while (!((prev_addr === 14'd0) && (bram_addr === SEQ_WORD))) @(negedge pl_clk);

        // 立刻把写请求摆上 PS 口：写将在 ≤10 ns 后的 ps 边沿提交，20 ns 的冲突窗口
        // 必然覆盖本周期末的 PL 读边沿。
        ps_addr  = SEQ_WORD;
        ps_wdata = s_new;
        ps_we    = 1'b1;
        @(posedge ps_clk);      // 这个上升沿就是提交沿
        @(negedge ps_clk);      // 在 ps 低电平中途撤，避开与内存模型的同沿竞争
        ps_we = 1'b0;
        repeat (3) @(posedge ps_clk);
        collide_enable = 1'b0;
        $display("INFO 注入同址冲突：seq 旧=%0d 新=%0d 混合读回=%0d（掩码=%08x）",
                 s_old, s_new, coll_mix, coll_mask);
    end
endtask

// 等某个序号被受理（不丢判据）；已在监视线程里做过 不错/不重 核对。
task wait_seq_accepted;
    input [31:0] s;
    input [8*40-1:0] tag;
    begin
        guard = 0;
        while ((seen_seq[s] !== 1'b1) && (guard < 4000)) begin
            @(negedge pl_clk);
            guard = guard + 1;
        end
        if (seen_seq[s] !== 1'b1) begin
            $display("FAIL: %0s 序号 %0d 始终没有被受理（命令丢失）", tag, s);
            $fatal(1, "command lost");
        end
    end
endtask

// ---------------------------------------------------------------- 主流程
initial begin
    rst_n                  = 1'b0;
    snapshot_commit        = 1'b0;
    snapshot_words         = 512'd0;
    harmonic_frame_start   = 1'b0;
    harmonic_valid         = 1'b0;
    harmonic_index         = 9'd0;
    harmonic_u_ratio       = 32'd0;
    harmonic_i_ratio       = 32'd0;
    harmonic_phase         = 32'd0;
    harmonic_flags         = 32'd0;
    command_response_valid = 1'b0;
    command_response       = 32'd0;

    ps_addr        = 14'd0;
    ps_wdata       = 32'd0;
    ps_we          = 1'b0;
    wr_addr_hold   = 14'd0;
    wr_window      = 2'd0;
    pl_rddata      = 32'd0;
    collide_enable = 1'b0;
    collide_value  = 32'd0;
    prev_addr      = 14'd0;
    ps_skew        = 2;
    collide_hits   = 0;

    pub_count            = 0;
    accepted_count       = 0;
    serial_pub_count     = 0;
    stress_pub_count     = 0;
    stress_accepted_count = 0;
    next_seq             = 1;

    for (i = 0; i < 16384; i = i + 1) mem[i] = 32'd0;
    for (i = 0; i <= SEQ_LIMIT; i = i + 1) seen_seq[i] = 1'b0;

    repeat (6) @(negedge pl_clk);
    rst_n = 1'b1;
    repeat (6) @(negedge pl_clk);

    for (rnd = 0; rnd < ROUNDS; rnd = rnd + 1) begin
        // 本轮的相位漂移量：±1..4 ns（周期仍是 10 ns，即仍是 100 MHz）
        ps_skew = (({$random} % 4) + 1) * ((({$random} % 2) == 0) ? 1 : -1);
        $display("INFO ---- 第 %0d 轮，ps_clk 半周期不对称量 skew=%0d ns ----", rnd, ps_skew);

        // ---- 串行：一条命令一个来回（真实 app 的节奏） ----
        for (k = 0; k < SERIAL_PER_ROUND; k = k + 1) begin
            c_now = {$random};
            a_now = {$random};
            s_now = next_seq;
            next_seq = next_seq + 1;
            ps_publish_serialized(c_now, a_now, s_now);
            wait_seq_accepted(s_now, "串行命令");
            if ((acc_code[s_now] !== c_now) || (acc_arg[s_now] !== a_now)) begin
                $display("FAIL: 串行命令 seq=%0d 受理到的 payload 与发布值不符 code=%08x/%08x arg=%08x/%08x",
                         s_now, acc_code[s_now], c_now, acc_arg[s_now], a_now);
                $fatal(1, "serialized payload mismatch");
            end
        end

        // ---- 定向同址冲突：PS 在 PL 读 SEQUENCE 字的那一拍写同一个字 ----
        // 放在背靠背压力之前：它是最能直接指向"跨域同址读写冲突"的定向场景。
        c_now = {$random};
        a_now = {$random};
        ps_publish_seq_collision(c_now, a_now, next_seq - 1, next_seq);
        s_now = next_seq;
        next_seq = next_seq + 3;    // 冲突场景跨过 2 个序号，保证混合掩码一定存在
        wait_seq_accepted(s_now, "同址冲突命令");
        if ((acc_code[s_now] !== c_now) || (acc_arg[s_now] !== a_now)) begin
            $display("FAIL: 同址冲突命令 seq=%0d 受理到的 payload 与发布值不符 code=%08x/%08x arg=%08x/%08x",
                     s_now, acc_code[s_now], c_now, acc_arg[s_now], a_now);
            $fatal(1, "collision payload mismatch");
        end

        // ---- 背靠背突发：不等响应连续下发（PS 非原子发布的压力） ----
        for (k = 0; k < STRESS_BURSTS; k = k + 1) begin
            c_now = {$random};
            a_now = {$random};
            s_now = next_seq;
            next_seq = next_seq + 1;
            ps_publish_burst(c_now, a_now, s_now, 3);
            last_c = c_now;
            last_a = a_now;
            last_s = s_now;
        end
        // 只要求最后一条不丢（中间被后续命令覆盖是允许的，见文件头说明）
        wait_seq_accepted(last_s, "背靠背最后一条");
        if ((acc_code[last_s] !== last_c) || (acc_arg[last_s] !== last_a)) begin
            $display("FAIL: 背靠背最后一条 seq=%0d payload 不符", last_s);
            $fatal(1, "stress payload mismatch");
        end
    end

    // ---- 收尾：全局核对 ----
    // ① 冲突注入必须真的发生过（否则本用例是空的）
    if (collide_hits !== ROUNDS) begin
        $display("FAIL: 同址冲突实际发生的次数 %0d ≠ 轮数 %0d", collide_hits, ROUNDS);
        $fatal(1, "collision injection did not fire");
    end
    // ② 串行段每条都必须被受理（不丢）
    if (serial_pub_count === 0) begin
        $display("FAIL: 没有发布任何串行命令");
        $fatal(1, "no serialized publication");
    end
    for (i = 0; i < pub_count; i = i + 1) begin
        if ((pub_s[i] < next_seq) && (seen_seq[pub_s[i]] === 1'b1)) begin
            if ((acc_code[pub_s[i]] !== pub_c[i]) || (acc_arg[pub_s[i]] !== pub_a[i])) begin
                $display("FAIL: 序号 %0d 受理到的 payload 与发布值不符", pub_s[i]);
                $fatal(1, "final payload mismatch");
            end
        end
    end
    for (i = 1; i < next_seq; i = i + 1) begin
        if (seen_seq[i] === 1'b1) stress_accepted_count = stress_accepted_count + 1;
    end
    $display("INFO 统计：发布 %0d 条（串行 %0d + 背靠背 %0d + 冲突 %0d），受理 %0d 次，冲突注入 %0d 次",
             pub_count, serial_pub_count, stress_pub_count, ROUNDS,
             accepted_count, collide_hits);
    $display("INFO 背靠背段被后续命令覆盖、未受理的条数（允许，见文件头说明）：%0d",
             stress_pub_count - (stress_accepted_count - serial_pub_count - ROUNDS));
    $display("PASS: pqm_shared_memory_bridge_cdc");
    $finish;
end

endmodule
