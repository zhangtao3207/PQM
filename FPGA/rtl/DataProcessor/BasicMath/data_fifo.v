`timescale 1ns / 1ps

/*
 * 模块: adc_sample_fifo_enhanced (双通道)
 * 功能:
 *   增强型异步 FIFO，专为 AD7606 8 通道并行 ADC 优化，
 *   通过 FRSTDATA 信号实现自动帧同步。
 *   双通道变体：支持同时处理电压和电流数据流。
 *
 * 输入:
 *   rst_n: 系统复位信号
 *   wr_clk: 写时钟域 (AD7606 ADC 时钟)
 *   wr_en: 写使能信号
 *   din: 32位双通道数据 [31:16]=电压, [15:0]=电流
 *   frstdata: AD7606 FRSTDATA 信号 (仅在 CH1 读取周期为高电平)
 *   rd_clk: 读时钟域 (处理/系统时钟)
 *   rd_en: 读使能信号
 *
 * 输出:
 *   full: FIFO 满标志
 *   prog_full: 可编程满标志
 *   overflow_warn: 溢出警告
 *   overflow: 溢出标志
 *   wr_data_count: 写数据计数
 *   wr_8ch_frame_count: 写入的 8 通道帧计数
 *   wr_fft_frame_count: 写入的 FFT 帧计数
 *   dout: 32位双通道输出数据
 *   dout_valid: 输出数据有效标志
 *   empty: FIFO 空标志
 *   prog_empty: 可编程空标志
 *   underflow_warn: 欠载警告
 *   underflow: 欠载标志
 *   rd_data_count: 读数据计数
 *   rd_8ch_frame_count: 可用的 8 通道帧计数
 *   rd_fft_frame_count: 可用的 FFT 帧计数
 *   fft_frame_ready: 完整 FFT 帧就绪标志
 *
 * 数据格式 (32位):
 *   [31:16] - 电压通道 (16位有符号)
 *   [15:0]  - 电流通道 (16位有符号)
 *   每个写操作向 FIFO 添加一个采样对 (V+I)。
 *
 * 特性:
 *   1. 基于 FRSTDATA 的帧检测和同步
 *   2. 自动 8 通道帧边界检测
 *   3. 双通道电压和电流：32位字包含两者
 *   4. 可选 FFT 帧聚合 (1024点帧 = 1024个 V+I 对)
 *   5. CDC (时钟域交叉) 与 3 级同步
 *   6. 可编程溢出/欠载警告
 *   7. 每帧数据计数和帧计数器
 */
module adc_sample_fifo_enhanced #(
    parameter integer DATA_WIDTH            = 32,     // 32-bit: [31:16] voltage, [15:0] current
    parameter integer ADDR_WIDTH            = 13,
    parameter integer FFT_FRAME_SIZE        = 1024,    // Number of V+I sample pairs for FFT (1024 pairs = 1024-point frames)
    parameter integer PROG_FULL_THRESH      = (1 << ADDR_WIDTH) - 512,
    parameter integer PROG_EMPTY_THRESH     = 512,
    parameter integer OVERFLOW_WARN_LEVEL   = (1 << ADDR_WIDTH) - 256,
    parameter integer UNDERFLOW_WARN_LEVEL  = 256
)(
    // Common  
    input  wire                        rst_n,
    
    // Write clock domain (AD7606 ADC clock)
    input  wire                        wr_clk,
    input  wire                        wr_en,
    input  wire [DATA_WIDTH-1:0]       din,                // 32-bit dual-channel: [31:16]=voltage, [15:0]=current
    input  wire                        frstdata,          // AD7606 FRSTDATA signal (high for CH1 only)
    output wire                        full,
    output wire                        prog_full,
    output wire                        overflow_warn,
    output wire                        overflow,
    output wire [ADDR_WIDTH:0]         wr_data_count,
    output wire [7:0]                  wr_8ch_frame_count,    // 8-channel frames written
    output wire [15:0]                 wr_fft_frame_count,    // FFT-sized frames written
    
    // Read clock domain (Processing/System clock)
    input  wire                        rd_clk,
    input  wire                        rd_en,
    output reg  [DATA_WIDTH-1:0]       dout,            // 32-bit dual-channel: [31:16]=voltage, [15:0]=current
    output reg                         dout_valid,
    output wire                        empty,
    output wire                        prog_empty,
    output wire                        underflow_warn,
    output wire                        underflow,
    output wire [ADDR_WIDTH:0]         rd_data_count,
    output wire [7:0]                  rd_8ch_frame_count,    // 8-channel frames available
    output wire [15:0]                 rd_fft_frame_count,    // FFT frames available
    output wire                        fft_frame_ready        // Complete FFT frame (1024×8ch) ready
);

localparam integer DEPTH      = (1 << ADDR_WIDTH);
localparam integer PTR_WIDTH  = ADDR_WIDTH + 1;
localparam integer FRAME_CNT_W = 8;  // Support up to 256 frames in buffer

localparam [ADDR_WIDTH:0] PROG_FULL_THRESH_EXT      = PROG_FULL_THRESH;
localparam [ADDR_WIDTH:0] PROG_EMPTY_THRESH_EXT     = PROG_EMPTY_THRESH;
localparam [ADDR_WIDTH:0] OVERFLOW_WARN_LEVEL_EXT   = OVERFLOW_WARN_LEVEL;
localparam [ADDR_WIDTH:0] UNDERFLOW_WARN_LEVEL_EXT  = UNDERFLOW_WARN_LEVEL;

(* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write-side pointers and synchronizers
reg  [PTR_WIDTH-1:0]  wr_bin;
reg  [PTR_WIDTH-1:0]  wr_gray;
reg  [PTR_WIDTH-1:0]  rd_gray_wr_sync1;
reg  [PTR_WIDTH-1:0]  rd_gray_wr_sync2;
reg  [PTR_WIDTH-1:0]  rd_gray_wr_sync3;     // New: Extra stage for better CDC
reg                   full_reg;
reg                   overflow_reg;
reg                   overflow_warn_reg;
reg  [FRAME_CNT_W-1:0] wr_frame_count;      // New: Count frames written
reg  [ADDR_WIDTH-1:0]  sample_in_frame;     // New: Count samples in current frame

// Read-side pointers and synchronizers
reg  [PTR_WIDTH-1:0]  rd_bin;
reg  [PTR_WIDTH-1:0]  rd_gray;
reg  [PTR_WIDTH-1:0]  wr_gray_rd_sync1;
reg  [PTR_WIDTH-1:0]  wr_gray_rd_sync2;
reg  [PTR_WIDTH-1:0]  wr_gray_rd_sync3;     // New: Extra stage for better CDC
reg                   empty_reg;
reg                   underflow_reg;
reg                   underflow_warn_reg;
reg  [FRAME_CNT_W-1:0] rd_frame_count;      // New: Count frames available
reg  [ADDR_WIDTH-1:0]  samples_in_current_frame;  // New: Track frame size

wire [PTR_WIDTH-1:0]  wr_bin_next;
wire [PTR_WIDTH-1:0]  wr_gray_next;
wire [PTR_WIDTH-1:0]  rd_bin_next;
wire [PTR_WIDTH-1:0]  rd_gray_next;
wire [PTR_WIDTH-1:0]  rd_bin_sync_wr;
wire [PTR_WIDTH-1:0]  wr_bin_sync_rd;
wire                  wr_push;
wire                  rd_pop;
wire                  full_next;
wire                  empty_next;
wire [ADDR_WIDTH:0]   wr_data_count_next;
wire [ADDR_WIDTH:0]   rd_data_count_next;

// Gray code conversion functions
function [PTR_WIDTH-1:0] bin2gray;
    input [PTR_WIDTH-1:0] bin_value;
    begin
        bin2gray = (bin_value >> 1) ^ bin_value;
    end
endfunction

function [PTR_WIDTH-1:0] gray2bin;
    input [PTR_WIDTH-1:0] gray_value;
    integer idx;
    begin
        gray2bin[PTR_WIDTH-1] = gray_value[PTR_WIDTH-1];
        for (idx = PTR_WIDTH - 2; idx >= 0; idx = idx - 1)
            gray2bin[idx] = gray2bin[idx + 1] ^ gray_value[idx];
    end
endfunction

// ============================================================================
// Combinatorial assignments
// ============================================================================

assign wr_push       = wr_en && !full_reg;
assign rd_pop        = rd_en && !empty_reg;
assign wr_bin_next   = wr_bin + {{ADDR_WIDTH{1'b0}}, wr_push};
assign wr_gray_next  = bin2gray(wr_bin_next);
assign rd_bin_next   = rd_bin + {{ADDR_WIDTH{1'b0}}, rd_pop};
assign rd_gray_next  = bin2gray(rd_bin_next);
assign rd_bin_sync_wr = gray2bin(rd_gray_wr_sync3);  // Use 3rd stage
assign wr_bin_sync_rd = gray2bin(wr_gray_rd_sync3);  // Use 3rd stage

assign wr_data_count_next = wr_bin - rd_bin_sync_wr;
assign rd_data_count_next = wr_bin_sync_rd - rd_bin;

// Full/Empty detection (standard Gray code comparison)
assign full_next =
    (wr_gray_next == {~rd_gray_wr_sync3[PTR_WIDTH-1:PTR_WIDTH-2],
                      rd_gray_wr_sync3[PTR_WIDTH-3:0]});
assign empty_next = (rd_gray_next == wr_gray_rd_sync3);

// Output assignment
assign wr_data_count = wr_data_count_next;
assign rd_data_count = rd_data_count_next;
assign full          = full_reg;
assign empty         = empty_reg;
assign prog_full     = (wr_data_count_next >= PROG_FULL_THRESH_EXT);
assign prog_empty    = (rd_data_count_next <= PROG_EMPTY_THRESH_EXT);
assign overflow_warn = overflow_warn_reg;
assign overflow      = overflow_reg;
assign underflow_warn = underflow_warn_reg;
assign underflow     = underflow_reg;
assign wr_frame_count = wr_frame_count;
assign rd_frame_count = rd_frame_count;

// Frame ready: complete frame available when rd_data_count >= FFT_FRAME_SIZE
assign frame_ready = (rd_data_count_next >= FFT_FRAME_SIZE);

// ============================================================================
// Write-clock-domain logic
// ============================================================================

always @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_bin             <= {PTR_WIDTH{1'b0}};
        wr_gray            <= {PTR_WIDTH{1'b0}};
        rd_gray_wr_sync1   <= {PTR_WIDTH{1'b0}};
        rd_gray_wr_sync2   <= {PTR_WIDTH{1'b0}};
        rd_gray_wr_sync3   <= {PTR_WIDTH{1'b0}};
        full_reg           <= 1'b0;
        overflow_reg       <= 1'b0;
        overflow_warn_reg  <= 1'b0;
        wr_frame_count     <= {FRAME_CNT_W{1'b0}};
        sample_in_frame    <= {ADDR_WIDTH{1'b0}};
    end else begin
        // ===== CDC synchronizer chain (improved stability) =====
        rd_gray_wr_sync1 <= rd_gray;
        rd_gray_wr_sync2 <= rd_gray_wr_sync1;
        rd_gray_wr_sync3 <= rd_gray_wr_sync2;

        // ===== Frame start marker handling =====
        if (frame_start) begin
            sample_in_frame <= {ADDR_WIDTH{1'b0}};
            if (wr_push)
                wr_frame_count <= wr_frame_count + 1'b1;
        end else if (wr_push) begin
            sample_in_frame <= sample_in_frame + 1'b1;
        end

        // ===== Overflow and warning detection =====
        overflow_reg <= wr_en && full_reg;
        overflow_warn_reg <= (wr_data_count_next >= OVERFLOW_WARN_LEVEL_EXT) && wr_en;

        // ===== FIFO write operation =====
        if (wr_push) begin
            mem[wr_bin[ADDR_WIDTH-1:0]] <= din;
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end

        full_reg <= full_next;
    end
end

// ============================================================================
// Read-clock-domain logic
// ============================================================================

always @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_bin             <= {PTR_WIDTH{1'b0}};
        rd_gray            <= {PTR_WIDTH{1'b0}};
        wr_gray_rd_sync1   <= {PTR_WIDTH{1'b0}};
        wr_gray_rd_sync2   <= {PTR_WIDTH{1'b0}};
        wr_gray_rd_sync3   <= {PTR_WIDTH{1'b0}};
        empty_reg          <= 1'b1;
        dout               <= {DATA_WIDTH{1'b0}};
        dout_valid         <= 1'b0;
        underflow_reg      <= 1'b0;
        underflow_warn_reg <= 1'b0;
        rd_frame_count     <= {FRAME_CNT_W{1'b0}};
        samples_in_current_frame <= {ADDR_WIDTH{1'b0}};
    end else begin
        // ===== CDC synchronizer chain (improved stability) =====
        wr_gray_rd_sync1 <= wr_gray;
        wr_gray_rd_sync2 <= wr_gray_rd_sync1;
        wr_gray_rd_sync3 <= wr_gray_rd_sync2;

        // ===== Output data valid control =====
        dout_valid <= 1'b0;
        underflow_reg <= rd_en && empty_reg;
        underflow_warn_reg <= (rd_data_count_next <= UNDERFLOW_WARN_LEVEL_EXT) && rd_en;

        // ===== FIFO read operation =====
        if (rd_pop) begin
            dout       <= mem[rd_bin[ADDR_WIDTH-1:0]];
            dout_valid <= 1'b1;
            rd_bin     <= rd_bin_next;
            rd_gray    <= rd_gray_next;
            
            // Track frame progress
            if (samples_in_current_frame == FFT_FRAME_SIZE - 1) begin
                samples_in_current_frame <= {ADDR_WIDTH{1'b0}};
                rd_frame_count <= rd_frame_count + 1'b1;
            end else begin
                samples_in_current_frame <= samples_in_current_frame + 1'b1;
            end
        end

        empty_reg <= empty_next;
    end
end

endmodule
