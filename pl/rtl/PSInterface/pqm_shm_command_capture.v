`timescale 1ns / 1ps
`include "pqm_shared_memory_map.vh"

/*
 * 模块名称：pqm_shm_command_capture
 * 功能说明：把 PS 写在共享内存命令区的三个 word（REQUEST / ARGUMENT / SEQUENCE）
 *   读成一个"两遍完全一致"的三元组，供 pqm_shared_memory_bridge 发布给 PL 控制逻辑。
 *
 * 为什么需要它（跨时钟域）：
 *   共享内存是异步真双口 RAM：PS 从 PORTA（clk_fpga_0，100 MHz）写，PL 从 PORTB
 *   （clk_out1_clk_wiz_0，50 MHz）读，两时钟不同源（Vivado report_cdc 报
 *   "No Common Primary Clock"）。UG473 规定同址同时读写时 DOUT 未定义：PL 轮询命令
 *   序号的那一刻 PS 可能正在写同一个字，**单次读**可能拿到旧值或翻转中的值，于是出现
 *   "看到新序号、取到旧命令码/旧参数"的裂缝命令。
 *
 *   这里不能用常规两级同步器：PS 侧 app 的 ABI 冻结，命令区只有 32 位多比特字，
 *   没有可用的单比特 req/ack 通道可以同步。本模块改用"整条三元组连读两遍 + 逐字比对"：
 *   任何一处不同、或任一读回值含 X，就整轮丢弃、不产生 valid；只有两遍完全一致、
 *   序号非 0、且不同于上次已受理序号时才受理。这样"读的瞬间被抓到跳变"的 transient
 *   永远不会被当成命令发布出去；丢弃不等于丢失——PS 写完命令后内存恒定，桥下一轮
 *   轮询必定读到一致的三元组，因此协议是自愈的。
 *
 *   残余风险（固有、单侧无法消除，勿假装已覆盖）：PS 先写 REQUEST、再写 ARGUMENT、
 *   最后写 SEQUENCE，三条 AXI store 之间若出现长停顿，内存会真实地在一个窗口内保持
 *   "新 REQUEST + 旧 ARGUMENT + 旧 SEQUENCE"。任何只靠读的策略都无法判定这种状态，
 *   只能靠 PS 侧改成原子发布（或 ABI 增加原子发布令牌）。
 *
 * 输入端口：
 *   clk：PL 工作时钟（与共享内存 PORTB 同域）。
 *   rst_n：低有效复位。
 *   start：单拍请求；桥在预读到"可能是新命令"的序号后拉高一拍。忙时被忽略。
 *   bram_rddata：共享内存 PORTB 在该拍返回的同步读数据（一拍延迟）。
 * 输出端口：
 *   busy：占用 PORTB（本模块拉高期间桥必须让出 bram_addr 并保持 we=0）。
 *   bram_addr：本模块给出的字地址（只读，恒为命令区三个字之一）。
 *   command_code / command_argument / command_sequence：确认一致的三元组。
 *   command_valid：单拍；与 command_* 同拍有效。
 *   last_sequence：最近一次受理的序号（桥用它做响应回显）。
 *   reject_count：被丢弃的确认轮数（诊断 / 仿真观察）。
 * 双向端口：无。
 */
module pqm_shm_command_capture (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        busy,
    output reg  [13:0] bram_addr,
    input  wire [31:0] bram_rddata,
    output reg  [31:0] command_code,
    output reg  [31:0] command_argument,
    output reg  [31:0] command_sequence,
    output reg         command_valid,
    output reg  [31:0] last_sequence,
    output reg  [15:0] reject_count
);

// 一轮确认共七个读周期：
//   REQ_A/ARG_A/SEQ_A 为第一遍（地址在 REQ、ARG 两态给出），REQ_B/ARG_B/SEQ_B 为第二遍。
// 读口一拍延迟，所以在"给出地址的下一态"取值：
//   ST_ARG_A 取到 REQUEST(1)  ST_SEQ_A 取到 ARGUMENT(1)  ST_REQ_B 取到 SEQUENCE(1)
//   ST_ARG_B 取到 REQUEST(2)  ST_SEQ_B 取到 ARGUMENT(2)  ST_EVAL  取到 SEQUENCE(2)
localparam [2:0] ST_IDLE  = 3'd0;
localparam [2:0] ST_REQ_A = 3'd1;
localparam [2:0] ST_ARG_A = 3'd2;
localparam [2:0] ST_SEQ_A = 3'd3;
localparam [2:0] ST_REQ_B = 3'd4;
localparam [2:0] ST_ARG_B = 3'd5;
localparam [2:0] ST_SEQ_B = 3'd6;
localparam [2:0] ST_EVAL  = 3'd7;

reg  [2:0]  state;
reg  [31:0] code_a;
reg  [31:0] arg_a;
reg  [31:0] seq_a;
reg  [31:0] code_b;
reg  [31:0] arg_b;

// 一轮确认期间独占读口；ST_EVAL 不再读，但仍多占一拍，桥据此让位。
assign busy = (state != ST_IDLE);

// 六个读回值必须已知（无 X）、两遍逐字一致，且序号非 0、非上次已受理值。
// 用 === 而非 ==：X 一律判为不一致，失败方向朝"不受理"，不会放出未定义数据。
wire tuple_known = !((^code_a === 1'bx) || (^arg_a === 1'bx) || (^seq_a === 1'bx) ||
                     (^code_b === 1'bx) || (^arg_b === 1'bx) || (^bram_rddata === 1'bx));
wire tuple_match = (code_a === code_b) && (arg_a === arg_b) && (seq_a === bram_rddata);
wire seq_fresh   = (bram_rddata !== 32'd0) && (bram_rddata !== last_sequence);
wire accept      = tuple_known && tuple_match && seq_fresh;

// 只读命令区三个字，绝不出现在其它地址上。
always @* begin
    case (state)
        ST_REQ_A: bram_addr = `PQM_SHM_COMMAND_REQUEST_WORD;
        ST_ARG_A: bram_addr = `PQM_SHM_COMMAND_ARGUMENT_WORD;
        ST_SEQ_A: bram_addr = `PQM_SHM_COMMAND_SEQUENCE_WORD;
        ST_REQ_B: bram_addr = `PQM_SHM_COMMAND_REQUEST_WORD;
        ST_ARG_B: bram_addr = `PQM_SHM_COMMAND_ARGUMENT_WORD;
        ST_SEQ_B: bram_addr = `PQM_SHM_COMMAND_SEQUENCE_WORD;
        default:  bram_addr = `PQM_SHM_COMMAND_SEQUENCE_WORD;
    endcase
end

always @(posedge clk) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        code_a           <= 32'd0;
        arg_a            <= 32'd0;
        seq_a            <= 32'd0;
        code_b           <= 32'd0;
        arg_b            <= 32'd0;
        command_code     <= 32'd0;
        command_argument <= 32'd0;
        command_sequence <= 32'd0;
        command_valid    <= 1'b0;
        last_sequence    <= 32'd0;
        reject_count     <= 16'd0;
    end else begin
        command_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (start) state <= ST_REQ_A;
            end
            ST_REQ_A: begin
                state <= ST_ARG_A;
            end
            ST_ARG_A: begin
                code_a <= bram_rddata;      // 第一遍 REQUEST
                state  <= ST_SEQ_A;
            end
            ST_SEQ_A: begin
                arg_a <= bram_rddata;       // 第一遍 ARGUMENT
                state <= ST_REQ_B;
            end
            ST_REQ_B: begin
                seq_a <= bram_rddata;       // 第一遍 SEQUENCE
                state <= ST_ARG_B;
            end
            ST_ARG_B: begin
                code_b <= bram_rddata;      // 第二遍 REQUEST
                state  <= ST_SEQ_B;
            end
            ST_SEQ_B: begin
                arg_b <= bram_rddata;       // 第二遍 ARGUMENT
                state <= ST_EVAL;
            end
            ST_EVAL: begin
                // 本拍 bram_rddata 即第二遍 SEQUENCE；比对用的都是本拍已稳定的寄存器。
                if (accept) begin
                    command_code     <= code_a;
                    command_argument <= arg_a;
                    command_sequence <= bram_rddata;
                    command_valid    <= 1'b1;
                    last_sequence    <= bram_rddata;
                end else begin
                    reject_count <= reject_count + 1'b1;
                end
                state <= ST_IDLE;
            end
            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
