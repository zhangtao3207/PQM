`timescale 1ns / 1ps
`include "pqm_shared_memory_map.vh"

/*
 * 模块名称：pqm_shared_memory_bridge
 * 功能说明：通过双口 BRAM 向 PS 原子发布标量快照、双 bank 谐波和命令响应。
 * 输入端口：
 *   clk：共享内存发布时钟。
 *   rst_n：低有效同步逻辑复位。
 *   snapshot_commit：请求锁存并发布一组标量快照。
 *   snapshot_words：按 ABI 顺序排列的 16 个 32 位标量 word。
 *   harmonic_frame_start：请求开始向非活动 bank 发布一帧谐波。
 *   harmonic_valid：当前谐波条目有效。
 *   harmonic_index：当前谐波阶次，范围为 0 至 `PQM_SHM_HARMONIC_LAST_INDEX`（63，共 64 条）。
 *   harmonic_u_ratio：当前谐波电压幅值占比。
 *   harmonic_i_ratio：当前谐波电流幅值占比。
 *   harmonic_phase：当前谐波有符号相位差。
 *   harmonic_flags：当前谐波有效性和告警标志。
 *   command_response_valid：命令处理结果有效。
 *   command_response：命令处理结果数据。
 *   bram_rddata：双口 BRAM 在当前地址返回的同步读数据。
 * 输出端口：
 *   snapshot_ready：允许接收新的标量快照提交。
 *   harmonic_start_ready：允许开始新的谐波帧发布。
 *   harmonic_ready：允许接收当前谐波条目。
 *   command_valid：向 PL 控制逻辑发出的单拍命令脉冲。
 *   command_code：PS 请求的命令码。
 *   command_argument：PS 请求的命令参数。
 *   command_sequence：PS 请求的命令序号。
 *   command_response_ready：允许接收命令处理结果。
 *   snapshot_sequence：最近完成发布的标量快照序号。
 *   harmonic_generation：最近完成发布的谐波代数。
 *   active_harmonic_bank：PS 当前应读取的谐波 bank。
 *   bram_addr：双口 BRAM 的 word 地址。
 *   bram_wrdata：双口 BRAM 的写数据。
 *   bram_we：双口 BRAM 的按字节写使能。
 *   bram_en：双口 BRAM 端口使能。
 * 双向端口：无。
 */
module pqm_shared_memory_bridge (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          snapshot_commit,
    output wire          snapshot_ready,
    input  wire [511:0]  snapshot_words,
    input  wire          harmonic_frame_start,
    output wire          harmonic_start_ready,
    input  wire          harmonic_valid,
    output wire          harmonic_ready,
    input  wire   [8:0]  harmonic_index,
    input  wire  [31:0]  harmonic_u_ratio,
    input  wire  [31:0]  harmonic_i_ratio,
    input  wire  [31:0]  harmonic_phase,
    input  wire  [31:0]  harmonic_flags,
    output reg           command_valid,
    output reg   [31:0]  command_code,
    output reg   [31:0]  command_argument,
    output reg   [31:0]  command_sequence,
    input  wire          command_response_valid,
    output wire          command_response_ready,
    input  wire  [31:0]  command_response,
    output reg   [31:0]  snapshot_sequence,
    output reg   [31:0]  harmonic_generation,
    output reg           active_harmonic_bank,
    output reg   [13:0]  bram_addr,
    output reg   [31:0]  bram_wrdata,
    output reg    [3:0]  bram_we,
    output wire          bram_en,
    input  wire  [31:0]  bram_rddata
);

localparam [4:0] STATE_INIT              = 5'd0;
localparam [4:0] STATE_IDLE              = 5'd1;
localparam [4:0] STATE_SNAPSHOT_WRITE    = 5'd2;
localparam [4:0] STATE_SNAPSHOT_STATUS   = 5'd3;
localparam [4:0] STATE_SNAPSHOT_SEQUENCE = 5'd4;
localparam [4:0] STATE_HARMONIC_U        = 5'd5;
localparam [4:0] STATE_HARMONIC_I        = 5'd6;
localparam [4:0] STATE_HARMONIC_PHASE    = 5'd7;
localparam [4:0] STATE_HARMONIC_FLAGS    = 5'd8;
localparam [4:0] STATE_HARMONIC_GEN      = 5'd9;
localparam [4:0] STATE_HARMONIC_STATUS   = 5'd10;
localparam [4:0] STATE_POLL_SEQUENCE     = 5'd11;
localparam [4:0] STATE_CHECK_SEQUENCE    = 5'd12;
localparam [4:0] STATE_CAPTURE_CODE      = 5'd13;
localparam [4:0] STATE_CAPTURE_ARGUMENT  = 5'd14;
localparam [4:0] STATE_RESPONSE_DATA     = 5'd15;
localparam [4:0] STATE_RESPONSE_SEQUENCE = 5'd16;

localparam [13:0] HARMONIC_BANK0_ADDR = `PQM_SHM_HARMONIC_BANK0_WORD;
localparam [13:0] HARMONIC_BANK1_ADDR = `PQM_SHM_HARMONIC_BANK1_WORD;

reg  [4:0]   state;
reg  [2:0]   init_index;
reg  [3:0]   snapshot_index;
reg  [511:0] snapshot_latched;
reg          snapshot_published;
reg          harmonic_published;
reg          harmonic_frame_active;
reg          harmonic_target_bank;
reg  [8:0]   harmonic_index_latched;
reg  [31:0]  harmonic_u_latched;
reg  [31:0]  harmonic_i_latched;
reg  [31:0]  harmonic_phase_latched;
reg  [31:0]  harmonic_flags_latched;
reg  [31:0]  pending_command_sequence;
reg  [31:0]  last_command_sequence;
reg  [31:0]  response_latched;
reg  [31:0]  response_sequence_latched;
wire [13:0]  harmonic_base_addr;
wire [13:0]  harmonic_entry_addr;

// 初始化阶段按地址返回固定协议头内容。
function [31:0] select_init_word;
    input [2:0] index;
    begin
        case (index)
            3'd0: select_init_word = `PQM_SHM_MAGIC;
            3'd1: select_init_word = `PQM_SHM_ABI_VERSION;
            3'd2: select_init_word = 32'd0;
            3'd3: select_init_word = 32'd0;
            3'd4: select_init_word = 32'd0;
            3'd5: select_init_word = `PQM_SHM_CAPABILITIES;
            default: select_init_word = 32'd0;
        endcase
    end
endfunction

// 从锁存的 512 位快照中选择一个固定 32 位 ABI word。
function [31:0] select_snapshot_word;
    input [511:0] words;
    input [3:0] index;
    begin
        case (index)
            4'd0:  select_snapshot_word = words[31:0];
            4'd1:  select_snapshot_word = words[63:32];
            4'd2:  select_snapshot_word = words[95:64];
            4'd3:  select_snapshot_word = words[127:96];
            4'd4:  select_snapshot_word = words[159:128];
            4'd5:  select_snapshot_word = words[191:160];
            4'd6:  select_snapshot_word = words[223:192];
            4'd7:  select_snapshot_word = words[255:224];
            4'd8:  select_snapshot_word = words[287:256];
            4'd9:  select_snapshot_word = words[319:288];
            4'd10: select_snapshot_word = words[351:320];
            4'd11: select_snapshot_word = words[383:352];
            4'd12: select_snapshot_word = words[415:384];
            4'd13: select_snapshot_word = words[447:416];
            4'd14: select_snapshot_word = words[479:448];
            4'd15: select_snapshot_word = words[511:480];
            default: select_snapshot_word = 32'd0;
        endcase
    end
endfunction

// BRAM 端口在所有状态保持使能，以支持串行写和同步命令轮询。
assign bram_en = 1'b1;

// 仅在完全空闲且未发布谐波帧时接收新标量快照。
assign snapshot_ready = (state == STATE_IDLE) && !harmonic_frame_active;

// 仅在完全空闲且无活动谐波帧时接收新帧开始请求。
assign harmonic_start_ready = (state == STATE_IDLE) && !harmonic_frame_active && !snapshot_commit;

// 活动谐波帧等待下一条目时向上游提供握手许可。
assign harmonic_ready = (state == STATE_IDLE) && harmonic_frame_active;

// 命令发布和谐波发布均空闲时接收命令处理结果。
assign command_response_ready = (state == STATE_IDLE)
                              && !harmonic_frame_active
                              && !snapshot_commit
                              && !harmonic_frame_start;

// 根据待发布 bank 选择谐波窗口基地址。
assign harmonic_base_addr = harmonic_target_bank ? HARMONIC_BANK1_ADDR : HARMONIC_BANK0_ADDR;

// 每个谐波条目占四个 word，使用左移形成条目基地址。
assign harmonic_entry_addr = harmonic_base_addr + {harmonic_index_latched, 2'b00};

// 按当前发布状态生成唯一 BRAM 地址、写数据和写使能。
always @* begin
    bram_addr   = 14'd0;
    bram_wrdata = 32'd0;
    bram_we     = 4'b0000;

    case (state)
        STATE_INIT: begin
            bram_addr   = {11'd0, init_index};
            bram_wrdata = select_init_word(init_index);
            bram_we     = 4'b1111;
        end
        STATE_SNAPSHOT_WRITE: begin
            bram_addr   = `PQM_SHM_SCALAR_BASE_WORD + snapshot_index;
            bram_wrdata = select_snapshot_word(snapshot_latched, snapshot_index);
            bram_we     = 4'b1111;
        end
        STATE_SNAPSHOT_STATUS: begin
            bram_addr   = `PQM_SHM_STATUS_WORD;
            bram_wrdata = `PQM_SHM_STATUS_SNAPSHOT_VALID
                        | (active_harmonic_bank ? `PQM_SHM_STATUS_HARMONIC_BANK : 32'd0)
                        | (harmonic_published ? `PQM_SHM_STATUS_HARMONIC_VALID : 32'd0);
            bram_we     = 4'b1111;
        end
        STATE_SNAPSHOT_SEQUENCE: begin
            bram_addr   = `PQM_SHM_SNAPSHOT_SEQ_WORD;
            bram_wrdata = snapshot_sequence + 1'b1;
            bram_we     = 4'b1111;
        end
        STATE_HARMONIC_U: begin
            bram_addr   = harmonic_entry_addr;
            bram_wrdata = harmonic_u_latched;
            bram_we     = 4'b1111;
        end
        STATE_HARMONIC_I: begin
            bram_addr   = harmonic_entry_addr + 1'b1;
            bram_wrdata = harmonic_i_latched;
            bram_we     = 4'b1111;
        end
        STATE_HARMONIC_PHASE: begin
            bram_addr   = harmonic_entry_addr + 2'd2;
            bram_wrdata = harmonic_phase_latched;
            bram_we     = 4'b1111;
        end
        STATE_HARMONIC_FLAGS: begin
            bram_addr   = harmonic_entry_addr + 2'd3;
            bram_wrdata = harmonic_flags_latched;
            bram_we     = 4'b1111;
        end
        STATE_HARMONIC_GEN: begin
            bram_addr   = `PQM_SHM_HARMONIC_GENERATION_WORD;
            bram_wrdata = harmonic_generation + 1'b1;
            bram_we     = 4'b1111;
        end
        STATE_HARMONIC_STATUS: begin
            bram_addr   = `PQM_SHM_STATUS_WORD;
            bram_wrdata = (snapshot_published ? `PQM_SHM_STATUS_SNAPSHOT_VALID : 32'd0)
                        | (harmonic_target_bank ? `PQM_SHM_STATUS_HARMONIC_BANK : 32'd0)
                        | `PQM_SHM_STATUS_HARMONIC_VALID;
            bram_we     = 4'b1111;
        end
        STATE_POLL_SEQUENCE: begin
            bram_addr = `PQM_SHM_COMMAND_SEQUENCE_WORD;
        end
        STATE_CHECK_SEQUENCE: begin
            bram_addr = `PQM_SHM_COMMAND_REQUEST_WORD;
        end
        STATE_CAPTURE_CODE: begin
            bram_addr = `PQM_SHM_COMMAND_ARGUMENT_WORD;
        end
        STATE_CAPTURE_ARGUMENT: begin
            bram_addr = `PQM_SHM_COMMAND_SEQUENCE_WORD;
        end
        STATE_RESPONSE_DATA: begin
            bram_addr   = `PQM_SHM_COMMAND_RESPONSE_WORD;
            bram_wrdata = response_latched;
            bram_we     = 4'b1111;
        end
        STATE_RESPONSE_SEQUENCE: begin
            bram_addr   = `PQM_SHM_COMMAND_RESPONSE_SEQ_WORD;
            bram_wrdata = response_sequence_latched;
            bram_we     = 4'b1111;
        end
        default: begin
            bram_addr   = 14'd0;
            bram_wrdata = 32'd0;
            bram_we     = 4'b0000;
        end
    endcase
end

// 串行调度初始化、快照、谐波、命令读取和响应提交。
always @(posedge clk) begin
    if (!rst_n) begin
        state                     <= STATE_INIT;
        init_index                <= 3'd0;
        snapshot_index            <= 4'd0;
        snapshot_latched          <= 512'd0;
        snapshot_published        <= 1'b0;
        harmonic_published        <= 1'b0;
        harmonic_frame_active     <= 1'b0;
        harmonic_target_bank      <= 1'b1;
        harmonic_index_latched    <= 9'd0;
        harmonic_u_latched        <= 32'd0;
        harmonic_i_latched        <= 32'd0;
        harmonic_phase_latched    <= 32'd0;
        harmonic_flags_latched    <= 32'd0;
        pending_command_sequence  <= 32'd0;
        last_command_sequence     <= 32'd0;
        response_latched          <= 32'd0;
        response_sequence_latched <= 32'd0;
        command_valid             <= 1'b0;
        command_code              <= 32'd0;
        command_argument          <= 32'd0;
        command_sequence          <= 32'd0;
        snapshot_sequence         <= 32'd0;
        harmonic_generation       <= 32'd0;
        active_harmonic_bank      <= 1'b0;
    end else begin
        command_valid <= 1'b0;

        case (state)
            STATE_INIT: begin
                if (init_index == 3'd5) begin
                    state <= STATE_IDLE;
                end else begin
                    init_index <= init_index + 1'b1;
                end
            end
            STATE_IDLE: begin
                if (harmonic_frame_active) begin
                    if (harmonic_valid) begin
                        harmonic_index_latched <= harmonic_index;
                        harmonic_u_latched     <= harmonic_u_ratio;
                        harmonic_i_latched     <= harmonic_i_ratio;
                        harmonic_phase_latched <= harmonic_phase;
                        harmonic_flags_latched <= harmonic_flags;
                        state                  <= STATE_HARMONIC_U;
                    end
                end else if (snapshot_commit) begin
                    snapshot_latched <= snapshot_words;
                    snapshot_index   <= 4'd0;
                    state            <= STATE_SNAPSHOT_WRITE;
                end else if (harmonic_frame_start) begin
                    harmonic_target_bank  <= !active_harmonic_bank;
                    harmonic_frame_active <= 1'b1;
                end else if (command_response_valid) begin
                    response_latched          <= command_response;
                    response_sequence_latched <= last_command_sequence;
                    state                     <= STATE_RESPONSE_DATA;
                end else begin
                    state <= STATE_POLL_SEQUENCE;
                end
            end
            STATE_SNAPSHOT_WRITE: begin
                if (snapshot_index == 4'd15) begin
                    state <= STATE_SNAPSHOT_STATUS;
                end else begin
                    snapshot_index <= snapshot_index + 1'b1;
                end
            end
            STATE_SNAPSHOT_STATUS: begin
                snapshot_published <= 1'b1;
                state              <= STATE_SNAPSHOT_SEQUENCE;
            end
            STATE_SNAPSHOT_SEQUENCE: begin
                snapshot_sequence <= snapshot_sequence + 1'b1;
                state             <= STATE_IDLE;
            end
            STATE_HARMONIC_U: begin
                state <= STATE_HARMONIC_I;
            end
            STATE_HARMONIC_I: begin
                state <= STATE_HARMONIC_PHASE;
            end
            STATE_HARMONIC_PHASE: begin
                state <= STATE_HARMONIC_FLAGS;
            end
            STATE_HARMONIC_FLAGS: begin
                // ABI 收敛后帧尾恒为 index 63（`PQM_SHM_HARMONIC_LAST_INDEX`），一帧共 64 条。
                if (harmonic_index_latched == `PQM_SHM_HARMONIC_LAST_INDEX) begin
                    state <= STATE_HARMONIC_GEN;
                end else begin
                    state <= STATE_IDLE;
                end
            end
            STATE_HARMONIC_GEN: begin
                harmonic_generation <= harmonic_generation + 1'b1;
                state               <= STATE_HARMONIC_STATUS;
            end
            STATE_HARMONIC_STATUS: begin
                active_harmonic_bank  <= harmonic_target_bank;
                harmonic_published    <= 1'b1;
                harmonic_frame_active <= 1'b0;
                state                 <= STATE_IDLE;
            end
            STATE_POLL_SEQUENCE: begin
                state <= STATE_CHECK_SEQUENCE;
            end
            STATE_CHECK_SEQUENCE: begin
                if ((bram_rddata != 32'd0) && (bram_rddata != last_command_sequence)) begin
                    pending_command_sequence <= bram_rddata;
                    state                    <= STATE_CAPTURE_CODE;
                end else begin
                    state <= STATE_IDLE;
                end
            end
            STATE_CAPTURE_CODE: begin
                command_code <= bram_rddata;
                state        <= STATE_CAPTURE_ARGUMENT;
            end
            STATE_CAPTURE_ARGUMENT: begin
                command_argument      <= bram_rddata;
                command_sequence      <= pending_command_sequence;
                last_command_sequence <= pending_command_sequence;
                command_valid         <= 1'b1;
                state                 <= STATE_IDLE;
            end
            STATE_RESPONSE_DATA: begin
                state <= STATE_RESPONSE_SEQUENCE;
            end
            STATE_RESPONSE_SEQUENCE: begin
                state <= STATE_IDLE;
            end
            default: begin
                state <= STATE_INIT;
            end
        endcase
    end
end

endmodule
