`timescale 1ns / 1ps

module ad7606_serial_ctrl #(
    parameter integer RESET_HIGH_CYCLES   = 8,      // ADC RESET 保持高电平的时钟周期数
    parameter integer CONVST_LOW_CYCLES   = 4,      // CONVST 低电平脉冲持续周期数
    parameter integer SCLK_LOW_CYCLES     = 20,     // SCLK 低电平持续周期数
    parameter integer SCLK_HIGH_CYCLES    = 20,     // SCLK 高电平持续周期数
    parameter integer BUSY_TIMEOUT_CYCLES = 100000  // BUSY 握手超时周期数
)(
    input  wire         clk,             // 控制状态机时钟
    input  wire         rst_n,           // 低有效复位
    input  wire         start,           // 启动一次采样的脉冲输入
    input  wire         soft_reset,      // 软件复位脉冲输入
    input  wire [2:0]   os_mode,         // 过采样模式配置
    input  wire         range_sel,       // 量程选择配置
    input  wire         busy_i,          // ADC BUSY 输入
    input  wire         frstdata_i,      // ADC FRSTDATA 输入，用于首通道起始对齐校验
    input  wire         sdata_i,         // ADC 串行数据输入
    output wire [2:0]   os_o,            // 输出到 ADC 的 OS[2:0]
    output wire         range_o,         // 输出到 ADC 的 RANGE
    output reg          reset_o,         // 输出到 ADC 的 RESET
    output reg          convst_o,        // 输出到 ADC 的 CONVST
    output reg          cs_n_o,          // 输出到 ADC 的 CS#
    output reg          sclk_o,          // 输出到 ADC 的串行时钟
    output reg [127:0]  data_frame_o,    // 8 通道拼接后的原始数据帧
    output reg          data_valid_o,    // 数据帧有效脉冲
    output reg          sample_active_o, // 采样流程忙标志
    output reg          timeout_o        // BUSY 握手超时标志
);

localparam [2:0] ST_RESET          = 3'd0; // 输出 ADC 复位脉冲的状态
localparam [2:0] ST_IDLE           = 3'd1; // 空闲等待 start 上升沿的状态
localparam [2:0] ST_CONV_LOW       = 3'd2; // 拉低 CONVST 的状态
localparam [2:0] ST_WAIT_BUSY_HIGH = 3'd3; // 等待 BUSY 拉高，确认 ADC 开始转换的状态
localparam [2:0] ST_WAIT_BUSY_LOW  = 3'd4; // 等待 BUSY 拉低，确认 ADC 转换完成的状态
localparam [2:0] ST_SCLK_LOW       = 3'd5; // 串行读数时输出 SCLK 低电平的状态
localparam [2:0] ST_SCLK_HIGH      = 3'd6; // 串行读数时输出 SCLK 高电平的状态

reg [2:0]  state;           // 串行控制状态机当前状态
reg [2:0]  channel_index;   // 当前正在读取的通道编号，范围 0~7
reg [4:0]  bit_index;       // 当前通道内已经读取到的位编号，范围 0~15
reg [15:0] shift_word;      // 串行移位寄存器，用于拼接一整个 16bit 通道数据
reg [31:0] counter;         // 通用延时计数器，用于复位、CONVST、SCLK 和超时控制
reg        start_d;         // start 延迟一拍后的值，用于检测启动上升沿
reg        soft_reset_d;    // soft_reset 延迟一拍后的值，用于检测软复位上升沿
reg [15:0] ila_ch1_data;    // 每次整帧采样完成后锁存的第 1 通道数据，供 ILA 观察

wire        start_rise;      // 启动信号上升沿脉冲
wire        soft_reset_rise; // 软件复位信号上升沿脉冲
wire [15:0] shift_word_next; // 在当前串行输入位拼入后的下一拍通道数据

// 直接透传 OS/RANGE 配置，并生成控制逻辑需要的边沿和移位组合信号
assign os_o            = os_mode;                      // 将过采样配置直接送到 ADC 管脚
assign range_o         = range_sel;                    // 将量程选择直接送到 ADC 管脚
assign start_rise      = start & ~start_d;             // 检测启动信号上升沿
assign soft_reset_rise = soft_reset & ~soft_reset_d;   // 检测软件复位上升沿
assign shift_word_next = {shift_word[14:0], sdata_i};  // 把当前串行输入位拼到移位寄存器最低位

// 主状态机：负责 ADC 复位、启动转换、等待 BUSY、串行移位取数以及输出有效脉冲
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= ST_RESET;
        channel_index   <= 3'd0;
        bit_index       <= 5'd0;
        shift_word      <= 16'd0;
        counter         <= RESET_HIGH_CYCLES - 1;
        start_d         <= 1'b0;
        soft_reset_d    <= 1'b0;
        ila_ch1_data    <= 16'd0;
        reset_o         <= 1'b1;
        convst_o        <= 1'b1;
        cs_n_o          <= 1'b1;
        sclk_o          <= 1'b1;
        data_frame_o    <= 128'd0;
        data_valid_o    <= 1'b0;
        sample_active_o <= 1'b1;
        timeout_o       <= 1'b0;
    end else begin
        start_d      <= start;
        soft_reset_d <= soft_reset;
        data_valid_o <= 1'b0;

        if (soft_reset_rise) begin
            state           <= ST_RESET;
            channel_index   <= 3'd0;
            bit_index       <= 5'd0;
            shift_word      <= 16'd0;
            counter         <= RESET_HIGH_CYCLES - 1;
            reset_o         <= 1'b1;
            convst_o        <= 1'b1;
            cs_n_o          <= 1'b1;
            sclk_o          <= 1'b1;
            data_frame_o    <= 128'd0;
            ila_ch1_data    <= 16'd0;
            sample_active_o <= 1'b1;
            timeout_o       <= 1'b0;
        end else case (state)
            ST_RESET: begin
                reset_o         <= 1'b1;
                convst_o        <= 1'b1;
                cs_n_o          <= 1'b1;
                sclk_o          <= 1'b1;
                sample_active_o <= 1'b1;
                timeout_o       <= 1'b0;

                if (counter == 0) begin
                    reset_o         <= 1'b0;
                    sample_active_o <= 1'b0;
                    state           <= ST_IDLE;
                end else begin
                    counter <= counter - 1'b1;
                end
            end

            ST_IDLE: begin
                reset_o         <= 1'b0;
                convst_o        <= 1'b1;
                cs_n_o          <= 1'b1;
                sclk_o          <= 1'b1;
                sample_active_o <= 1'b0;

                if (start_rise) begin
                    timeout_o       <= 1'b0;
                    data_frame_o    <= 128'd0;
                    convst_o        <= 1'b0;
                    counter         <= CONVST_LOW_CYCLES - 1;
                    state           <= ST_CONV_LOW;
                    sample_active_o <= 1'b1;
                end
            end

            ST_CONV_LOW: begin
                convst_o <= 1'b0;

                if (counter == 0) begin
                    convst_o <= 1'b1;
                    counter  <= BUSY_TIMEOUT_CYCLES - 1;
                    state    <= ST_WAIT_BUSY_HIGH;
                end else begin
                    counter <= counter - 1'b1;
                end
            end

            ST_WAIT_BUSY_HIGH: begin
                convst_o <= 1'b1;

                if (busy_i) begin
                    counter <= BUSY_TIMEOUT_CYCLES - 1;
                    state   <= ST_WAIT_BUSY_LOW;
                end else if (counter == 0) begin
                    timeout_o       <= 1'b1;
                    sample_active_o <= 1'b0;
                    state           <= ST_IDLE;
                end else begin
                    counter <= counter - 1'b1;
                end
            end

            ST_WAIT_BUSY_LOW: begin
                if (!busy_i) begin
                    cs_n_o        <= 1'b0;
                    sclk_o        <= 1'b1;
                    channel_index <= 3'd0;
                    bit_index     <= 5'd0;
                    shift_word    <= 16'd0;
                    counter       <= SCLK_LOW_CYCLES - 1;
                    state         <= ST_SCLK_LOW;
                end else if (counter == 0) begin
                    timeout_o       <= 1'b1;
                    sample_active_o <= 1'b0;
                    state           <= ST_IDLE;
                end else begin
                    counter <= counter - 1'b1;
                end
            end

            ST_SCLK_LOW: begin
                cs_n_o <= 1'b0;
                sclk_o <= 1'b0;

                if (counter == 0) begin
                    // 第 1 通道第 1 bit 必须伴随 FRSTDATA 有效，
                    // 否则认为当前串行数据起点没有和通道边界对齐。
                    if ((channel_index == 3'd0) && (bit_index == 5'd0) && !frstdata_i) begin
                        cs_n_o          <= 1'b1;
                        sclk_o          <= 1'b1;
                        sample_active_o <= 1'b0;
                        timeout_o       <= 1'b1;
                        state           <= ST_IDLE;
                    end else begin
                        shift_word <= shift_word_next;
                        if (bit_index == 5'd15) begin
                            data_frame_o[(channel_index * 16) +: 16] <= shift_word_next;
                        end
                        sclk_o  <= 1'b1;
                        counter <= SCLK_HIGH_CYCLES - 1;
                        state   <= ST_SCLK_HIGH;
                    end
                end else begin
                    counter <= counter - 1'b1;
                end
            end

            ST_SCLK_HIGH: begin
                cs_n_o <= 1'b0;
                sclk_o <= 1'b1;

                if (counter == 0) begin
                    if (bit_index == 5'd15) begin
                        shift_word <= 16'd0;
                        bit_index  <= 5'd0;
                        if (channel_index == 3'd7) begin
                            cs_n_o          <= 1'b1;
                            ila_ch1_data    <= data_frame_o[15:0];
                            data_valid_o    <= 1'b1;
                            sample_active_o <= 1'b0;
                            state           <= ST_IDLE;
                        end else begin
                            channel_index <= channel_index + 1'b1;
                            counter       <= SCLK_LOW_CYCLES - 1;
                            state         <= ST_SCLK_LOW;
                        end
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        counter   <= SCLK_LOW_CYCLES - 1;
                        state     <= ST_SCLK_LOW;
                    end
                end else begin
                    counter <= counter - 1'b1;
                end
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

ILA_ADC_DRIVER u_ila_adc_serial (
    .clk(clk),
    .probe0(sdata_i),
    .probe1(busy_i),
    .probe2(reset_o),
    .probe3(convst_o),
    .probe4(cs_n_o),
    .probe5(sclk_o),
    .probe6(timeout_o),
    .probe7(ila_ch1_data)
);

endmodule
