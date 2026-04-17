`timescale 1ns / 1ps

/*
 * 模块: data_fifo
 * 功能:
 *   为 FFT 输入链路缓存双通道 ADC 采样对。写端持续接收 U/I 采样对，读端按 FFT 帧长度
 *   取出连续样本，隔离 ADC 采样节拍与 xfft_0 AXI-Stream 输入握手。
 *
 * 输入:
 *   rst_n: 低有效复位信号。
 *   wr_clk: FIFO 写时钟，通常接 ADC 采样时钟。
 *   wr_en: 写入使能，拉高时尝试写入一个 U/I 采样对。
 *   din: 写入数据，[31:16] 为电压采样，[15:0] 为电流采样。
 *   frstdata: 可选帧标记输入，当前 FFT 链路仅用于调试计数。
 *   rd_clk: FIFO 读时钟，通常接 FFT 工作时钟。
 *   rd_en: 读出使能，拉高时尝试读出一个 U/I 采样对。
 *
 * 输出:
 *   full: FIFO 满标志。
 *   prog_full: FIFO 接近满标志。
 *   overflow_warn: 写端接近溢出告警。
 *   overflow: FIFO 满时继续写入的溢出标志。
 *   wr_data_count: 写端视角下的 FIFO 数据量。
 *   wr_8ch_frame_count: 写端 frstdata 标记计数，供调试观察。
 *   wr_fft_frame_count: 写端已累计写满的 FFT 帧计数。
 *   dout: 读出数据，[31:16] 为电压采样，[15:0] 为电流采样。
 *   dout_valid: 读出数据有效脉冲。
 *   empty: FIFO 空标志。
 *   prog_empty: FIFO 接近空标志。
 *   underflow_warn: 读端接近欠载告警。
 *   underflow: FIFO 空时继续读取的欠载标志。
 *   rd_data_count: 读端视角下的 FIFO 数据量。
 *   rd_8ch_frame_count: 兼容调试端口，当前输出已读 FFT 帧计数低 8 位。
 *   rd_fft_frame_count: 读端已完整读出的 FFT 帧计数。
 *   fft_frame_ready: 读端至少缓存一整帧 FFT 样本。
 */
module data_fifo #(
    parameter integer DATA_WIDTH            = 32,
    parameter integer ADDR_WIDTH            = 13,
    parameter integer FFT_FRAME_SIZE        = 2048,
    parameter integer PROG_FULL_THRESH      = (1 << ADDR_WIDTH) - 512,
    parameter integer PROG_EMPTY_THRESH     = 512,
    parameter integer OVERFLOW_WARN_LEVEL   = (1 << ADDR_WIDTH) - 256,
    parameter integer UNDERFLOW_WARN_LEVEL  = 256
)(
    input  wire                        rst_n,
    input  wire                        wr_clk,
    input  wire                        wr_en,
    input  wire [DATA_WIDTH-1:0]       din,
    input  wire                        frstdata,
    output wire                        full,
    output wire                        prog_full,
    output wire                        overflow_warn,
    output wire                        overflow,
    output wire [ADDR_WIDTH:0]         wr_data_count,
    output wire [7:0]                  wr_8ch_frame_count,
    output wire [15:0]                 wr_fft_frame_count,
    input  wire                        rd_clk,
    input  wire                        rd_en,
    output wire [DATA_WIDTH-1:0]       dout,
    output reg                         dout_valid,
    output wire                        empty,
    output wire                        prog_empty,
    output wire                        underflow_warn,
    output wire                        underflow,
    output wire [ADDR_WIDTH:0]         rd_data_count,
    output wire [7:0]                  rd_8ch_frame_count,
    output wire [15:0]                 rd_fft_frame_count,
    output wire                        fft_frame_ready
);

localparam integer DEPTH       = (1 << ADDR_WIDTH);
localparam integer PTR_WIDTH   = ADDR_WIDTH + 1;
localparam [ADDR_WIDTH:0] PROG_FULL_THRESH_EXT     = PROG_FULL_THRESH;
localparam [ADDR_WIDTH:0] PROG_EMPTY_THRESH_EXT    = PROG_EMPTY_THRESH;
localparam [ADDR_WIDTH:0] OVERFLOW_WARN_LEVEL_EXT  = OVERFLOW_WARN_LEVEL;
localparam [ADDR_WIDTH:0] UNDERFLOW_WARN_LEVEL_EXT = UNDERFLOW_WARN_LEVEL;
localparam [ADDR_WIDTH:0] FFT_FRAME_SIZE_EXT       = FFT_FRAME_SIZE;
localparam [ADDR_WIDTH-1:0] FFT_FRAME_LAST_SAMPLE  = FFT_FRAME_SIZE - 1;

reg  [PTR_WIDTH-1:0]  wr_bin;
reg  [PTR_WIDTH-1:0]  wr_gray;
reg  [PTR_WIDTH-1:0]  rd_gray_wr_sync1;
reg  [PTR_WIDTH-1:0]  rd_gray_wr_sync2;
reg  [PTR_WIDTH-1:0]  rd_gray_wr_sync3;
reg                   full_reg;
reg                   overflow_reg;
reg                   overflow_warn_reg;
reg  [ADDR_WIDTH-1:0] wr_sample_in_frame;
reg  [7:0]            wr_8ch_frame_count_reg;
reg  [15:0]           wr_fft_frame_count_reg;

reg  [PTR_WIDTH-1:0]  rd_bin;
reg  [PTR_WIDTH-1:0]  rd_gray;
reg  [PTR_WIDTH-1:0]  wr_gray_rd_sync1;
reg  [PTR_WIDTH-1:0]  wr_gray_rd_sync2;
reg  [PTR_WIDTH-1:0]  wr_gray_rd_sync3;
reg                   empty_reg;
reg                   underflow_reg;
reg                   underflow_warn_reg;
reg  [ADDR_WIDTH-1:0] rd_sample_in_frame;
reg  [15:0]           rd_fft_frame_count_reg;

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

// 直接实例化 FFT 输入 FIFO 专用 RAM IP，A 口写采样对，B 口按 FFT 读节拍输出。
blk_mem_gen_fft_fifo_ram u_blk_mem_gen_fft_fifo_ram (
    .clka  (wr_clk),
    .ena   (1'b1),
    .wea   ({wr_push}),
    .addra (wr_bin[ADDR_WIDTH-1:0]),
    .dina  (din),
    .clkb  (rd_clk),
    .enb   (rd_pop),
    .addrb (rd_bin[ADDR_WIDTH-1:0]),
    .doutb (dout)
);

// 将二进制指针转换为 Gray 码，供跨时钟域同步使用。
function [PTR_WIDTH-1:0] bin2gray;
    input [PTR_WIDTH-1:0] bin_value;
    begin
        bin2gray = (bin_value >> 1) ^ bin_value;
    end
endfunction

// 将同步后的 Gray 码指针恢复为二进制，便于计算 FIFO 数据量。
function [PTR_WIDTH-1:0] gray2bin;
    input [PTR_WIDTH-1:0] gray_value;
    integer idx;
    begin
        gray2bin[PTR_WIDTH-1] = gray_value[PTR_WIDTH-1];
        for (idx = PTR_WIDTH - 2; idx >= 0; idx = idx - 1)
            gray2bin[idx] = gray2bin[idx + 1] ^ gray_value[idx];
    end
endfunction

// 组合生成 FIFO 推入、弹出、指针和数据量状态。
assign wr_push          = wr_en && !full_reg;
assign rd_pop           = rd_en && !empty_reg;
assign wr_bin_next      = wr_bin + {{ADDR_WIDTH{1'b0}}, wr_push};
assign wr_gray_next     = bin2gray(wr_bin_next);
assign rd_bin_next      = rd_bin + {{ADDR_WIDTH{1'b0}}, rd_pop};
assign rd_gray_next     = bin2gray(rd_bin_next);
assign rd_bin_sync_wr   = gray2bin(rd_gray_wr_sync3);
assign wr_bin_sync_rd   = gray2bin(wr_gray_rd_sync3);
assign wr_data_count_next = wr_bin - rd_bin_sync_wr;
assign rd_data_count_next = wr_bin_sync_rd - rd_bin;

// 组合生成标准异步 FIFO 满空判断。
assign full_next =
    (wr_gray_next == {~rd_gray_wr_sync3[PTR_WIDTH-1:PTR_WIDTH-2],
                      rd_gray_wr_sync3[PTR_WIDTH-3:0]});
assign empty_next = (rd_gray_next == wr_gray_rd_sync3);

// 对外导出 FIFO 状态、调试计数和 FFT 帧可用标志。
assign wr_data_count     = wr_data_count_next;
assign rd_data_count     = rd_data_count_next;
assign full              = full_reg;
assign empty             = empty_reg;
assign prog_full         = (wr_data_count_next >= PROG_FULL_THRESH_EXT);
assign prog_empty        = (rd_data_count_next <= PROG_EMPTY_THRESH_EXT);
assign overflow_warn     = overflow_warn_reg;
assign overflow          = overflow_reg;
assign underflow_warn    = underflow_warn_reg;
assign underflow         = underflow_reg;
assign wr_8ch_frame_count = wr_8ch_frame_count_reg;
assign wr_fft_frame_count = wr_fft_frame_count_reg;
assign rd_8ch_frame_count = rd_fft_frame_count_reg[7:0];
assign rd_fft_frame_count = rd_fft_frame_count_reg;
assign fft_frame_ready   = (rd_data_count_next >= FFT_FRAME_SIZE_EXT);

// 写时钟域：同步读指针、写入采样对，并按 FFT 帧长度累计写帧计数。
always @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_bin                 <= {PTR_WIDTH{1'b0}};
        wr_gray                <= {PTR_WIDTH{1'b0}};
        rd_gray_wr_sync1       <= {PTR_WIDTH{1'b0}};
        rd_gray_wr_sync2       <= {PTR_WIDTH{1'b0}};
        rd_gray_wr_sync3       <= {PTR_WIDTH{1'b0}};
        full_reg               <= 1'b0;
        overflow_reg           <= 1'b0;
        overflow_warn_reg      <= 1'b0;
        wr_sample_in_frame     <= {ADDR_WIDTH{1'b0}};
        wr_8ch_frame_count_reg <= 8'd0;
        wr_fft_frame_count_reg <= 16'd0;
    end else begin
        rd_gray_wr_sync1 <= rd_gray;
        rd_gray_wr_sync2 <= rd_gray_wr_sync1;
        rd_gray_wr_sync3 <= rd_gray_wr_sync2;

        overflow_reg      <= wr_en && full_reg;
        overflow_warn_reg <= (wr_data_count_next >= OVERFLOW_WARN_LEVEL_EXT) && wr_en;

        if (wr_push) begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;

            if (frstdata)
                wr_8ch_frame_count_reg <= wr_8ch_frame_count_reg + 8'd1;

            if (wr_sample_in_frame == FFT_FRAME_LAST_SAMPLE) begin
                wr_sample_in_frame     <= {ADDR_WIDTH{1'b0}};
                wr_fft_frame_count_reg <= wr_fft_frame_count_reg + 16'd1;
            end else begin
                wr_sample_in_frame <= wr_sample_in_frame + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
            end
        end

        full_reg <= full_next;
    end
end

// 读时钟域：同步写指针、读出采样对，并按 FFT 帧长度累计读帧计数。
always @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_bin                 <= {PTR_WIDTH{1'b0}};
        rd_gray                <= {PTR_WIDTH{1'b0}};
        wr_gray_rd_sync1       <= {PTR_WIDTH{1'b0}};
        wr_gray_rd_sync2       <= {PTR_WIDTH{1'b0}};
        wr_gray_rd_sync3       <= {PTR_WIDTH{1'b0}};
        empty_reg              <= 1'b1;
        dout_valid             <= 1'b0;
        underflow_reg          <= 1'b0;
        underflow_warn_reg     <= 1'b0;
        rd_sample_in_frame     <= {ADDR_WIDTH{1'b0}};
        rd_fft_frame_count_reg <= 16'd0;
    end else begin
        wr_gray_rd_sync1 <= wr_gray;
        wr_gray_rd_sync2 <= wr_gray_rd_sync1;
        wr_gray_rd_sync3 <= wr_gray_rd_sync2;

        dout_valid        <= 1'b0;
        underflow_reg     <= rd_en && empty_reg;
        underflow_warn_reg <= (rd_data_count_next <= UNDERFLOW_WARN_LEVEL_EXT) && rd_en;

        if (rd_pop) begin
            dout_valid <= 1'b1;
            rd_bin     <= rd_bin_next;
            rd_gray    <= rd_gray_next;

            if (rd_sample_in_frame == FFT_FRAME_LAST_SAMPLE) begin
                rd_sample_in_frame     <= {ADDR_WIDTH{1'b0}};
                rd_fft_frame_count_reg <= rd_fft_frame_count_reg + 16'd1;
            end else begin
                rd_sample_in_frame <= rd_sample_in_frame + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
            end
        end

        empty_reg <= empty_next;
    end
end

endmodule
