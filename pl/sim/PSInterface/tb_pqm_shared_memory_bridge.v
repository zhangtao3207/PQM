`timescale 1ns / 1ps
`include "pqm_shared_memory_map.vh"

/*
 * 模块名称：tb_pqm_shared_memory_bridge
 * 功能说明：验证标量一致性提交、谐波双 bank 发布和 PS 命令响应序列。
 * 输入端口：无。
 * 输出端口：无。
 * 双向端口：无。
 */
module tb_pqm_shared_memory_bridge;

localparam [13:0] SNAPSHOT_SEQ_ADDR = `PQM_SHM_SNAPSHOT_SEQ_WORD;

reg          clk;
reg          rst_n;
reg          snapshot_commit;
wire         snapshot_ready;
reg  [511:0] snapshot_words;
reg          harmonic_frame_start;
wire         harmonic_start_ready;
reg          harmonic_valid;
wire         harmonic_ready;
reg    [8:0] harmonic_index;
reg   [31:0] harmonic_u_ratio;
reg   [31:0] harmonic_i_ratio;
reg   [31:0] harmonic_phase;
reg   [31:0] harmonic_flags;
wire         command_valid;
wire  [31:0] command_code;
wire  [31:0] command_argument;
wire  [31:0] command_sequence;
reg          command_response_valid;
wire         command_response_ready;
reg   [31:0] command_response;
wire  [31:0] snapshot_sequence;
wire  [31:0] harmonic_generation;
wire         active_harmonic_bank;
wire  [13:0] bram_addr;
wire  [31:0] bram_wrdata;
wire   [3:0] bram_we;
wire         bram_en;
reg   [31:0] bram_rddata;

reg [31:0] bram [0:16383];
integer memory_index;
integer check_index;
integer command_pulse_count;
reg [13:0] last_write_addr;

// 生成 100 MHz 仿真时钟。
always #5 clk = ~clk;

// 模拟真双口 BRAM 的 PL 端同步读和按字节写行为。
always @(posedge clk) begin
    if (bram_en) begin
        bram_rddata <= bram[bram_addr];
        if (bram_we[0]) bram[bram_addr][7:0]   <= bram_wrdata[7:0];
        if (bram_we[1]) bram[bram_addr][15:8]  <= bram_wrdata[15:8];
        if (bram_we[2]) bram[bram_addr][23:16] <= bram_wrdata[23:16];
        if (bram_we[3]) bram[bram_addr][31:24] <= bram_wrdata[31:24];
    end
end

// 记录最后一次 PL 写地址，用于确认快照序号最后提交。
always @(posedge clk) begin
    if (!rst_n) begin
        last_write_addr <= 14'd0;
    end else if (bram_en && (bram_we != 4'b0000)) begin
        last_write_addr <= bram_addr;
    end
end

// 统计命令脉冲，确认同一个 PS 序号不会被重复执行。
always @(posedge clk) begin
    if (!rst_n) begin
        command_pulse_count <= 0;
    end else if (command_valid) begin
        command_pulse_count <= command_pulse_count + 1;
    end
end

// 发送一个谐波条目，等待桥接器完成四个 word 的串行写入。
task send_harmonic_entry;
    input [8:0] entry_index;
    begin
        while (!harmonic_ready) @(negedge clk);
        harmonic_index   = entry_index;
        harmonic_u_ratio = 32'h10000000 + entry_index;
        harmonic_i_ratio = 32'h20000000 + entry_index;
        harmonic_phase   = 32'h30000000 + entry_index;
        harmonic_flags   = 32'h40000000 + entry_index;
        harmonic_valid   = 1'b1;
        @(negedge clk);
        harmonic_valid   = 1'b0;
    end
endtask

// 被测模块：独占 BRAM PL 端口并串行发布快照、谐波和命令响应。
pqm_shared_memory_bridge u_dut (
    .clk                    (clk),
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

// 主测试流程：依次检查初始化、快照、谐波 bank 切换和命令响应。
initial begin
    clk                    = 1'b0;
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
    bram_rddata            = 32'd0;
    command_pulse_count    = 0;
    last_write_addr        = 14'd0;

    for (memory_index = 0; memory_index < 16384; memory_index = memory_index + 1) begin
        bram[memory_index] = 32'd0;
    end

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    wait (snapshot_ready);
    @(negedge clk);

    if (bram[`PQM_SHM_MAGIC_WORD] != `PQM_SHM_MAGIC) $fatal(1, "magic initialization mismatch");
    if (bram[`PQM_SHM_ABI_WORD] != `PQM_SHM_ABI_VERSION) $fatal(1, "ABI initialization mismatch");

    snapshot_words = {
        32'hA500000F, 32'hA500000E, 32'hA500000D, 32'hA500000C,
        32'hA500000B, 32'hA500000A, 32'hA5000009, 32'hA5000008,
        32'hA5000007, 32'hA5000006, 32'hA5000005, 32'hA5000004,
        32'hA5000003, 32'hA5000002, 32'hA5000001, 32'hA5000000
    };
    snapshot_commit = 1'b1;
    @(negedge clk);
    snapshot_commit = 1'b0;
    snapshot_words = {
        32'hB600000F, 32'hB600000E, 32'hB600000D, 32'hB600000C,
        32'hB600000B, 32'hB600000A, 32'hB6000009, 32'hB6000008,
        32'hB6000007, 32'hB6000006, 32'hB6000005, 32'hB6000004,
        32'hB6000003, 32'hB6000002, 32'hB6000001, 32'hB6000000
    };

    wait (!snapshot_ready);
    wait (snapshot_ready);
    @(negedge clk);
    for (check_index = 0; check_index < 16; check_index = check_index + 1) begin
        if (bram[`PQM_SHM_SCALAR_BASE_WORD + check_index] != (32'hA5000000 + check_index)) begin
            $fatal(1, "snapshot payload was not latched coherently");
        end
    end
    if (bram[`PQM_SHM_SNAPSHOT_SEQ_WORD] != 32'd1) $fatal(1, "snapshot sequence mismatch");
    if (last_write_addr != SNAPSHOT_SEQ_ADDR) $fatal(1, "snapshot sequence was not written last");

    wait (harmonic_start_ready);
    harmonic_frame_start = 1'b1;
    @(negedge clk);
    harmonic_frame_start = 1'b0;
    wait (!harmonic_start_ready);
    for (check_index = 0; check_index <= 500; check_index = check_index + 1) begin
        send_harmonic_entry(check_index[8:0]);
    end
    wait (harmonic_start_ready);
    @(negedge clk);

    if (bram[`PQM_SHM_HARMONIC_BANK1_WORD] != 32'h10000000) $fatal(1, "harmonic bank first entry mismatch");
    if (bram[`PQM_SHM_HARMONIC_BANK1_WORD + (500 << 2) + 3] != 32'h400001F4) $fatal(1, "harmonic bank last entry mismatch");
    if (bram[`PQM_SHM_HARMONIC_GENERATION_WORD] != 32'd1) $fatal(1, "harmonic generation mismatch");
    if (!active_harmonic_bank) $fatal(1, "harmonic bank did not switch");

    bram[`PQM_SHM_COMMAND_REQUEST_WORD]  = 32'h00000022;
    bram[`PQM_SHM_COMMAND_ARGUMENT_WORD] = 32'h12345678;
    bram[`PQM_SHM_COMMAND_SEQUENCE_WORD] = 32'd7;
    wait (command_valid);
    #1;
    if (command_code != 32'h00000022) $fatal(1, "command code mismatch");
    if (command_argument != 32'h12345678) $fatal(1, "command argument mismatch");
    if (command_sequence != 32'd7) $fatal(1, "command sequence mismatch");

    wait (command_response_ready);
    @(negedge clk);
    command_response       = 32'hACCE0001;
    command_response_valid = 1'b1;
    @(negedge clk);
    command_response_valid = 1'b0;

    wait (bram[`PQM_SHM_COMMAND_RESPONSE_SEQ_WORD] == 32'd7);
    repeat (12) @(posedge clk);
    if (bram[`PQM_SHM_COMMAND_RESPONSE_WORD] != 32'hACCE0001) $fatal(1, "command response mismatch");
    if (command_pulse_count != 1) $fatal(1, "command was dispatched more than once");

    $display("PASS: pqm_shared_memory_bridge");
    $finish;
end

endmodule
