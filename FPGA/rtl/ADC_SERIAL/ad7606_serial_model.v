`timescale 1ns / 1ps

module ad7606_serial_model #(
    parameter integer T_CONV_NO_OS_NS = 4000,    // 不开过采样时的模拟转换时间
    parameter integer T_CONV_X2_NS    = 8700,    // 2 倍过采样时的模拟转换时间
    parameter integer T_CONV_X4_NS    = 16000,   // 4 倍过采样时的模拟转换时间
    parameter integer T_CONV_X8_NS    = 31000,   // 8 倍过采样时的模拟转换时间
    parameter integer T_CONV_X16_NS   = 62000,   // 16 倍过采样时的模拟转换时间
    parameter integer T_CONV_X32_NS   = 123000,  // 32 倍过采样时的模拟转换时间
    parameter integer T_CONV_X64_NS   = 286000   // 64 倍过采样时的模拟转换时间
)(
    input  wire       reset_i,   // 模型复位输入，高有效
    input  wire       convst_i,  // 模型转换启动输入
    input  wire       cs_n_i,    // 模型片选输入，低有效
    input  wire       sclk_i,    // 模型串行时钟输入
    input  wire [2:0] os_i,      // 模型过采样模式输入
    input  wire       range_i,   // 模型量程选择输入
    output reg        busy_o,    // 模型 BUSY 输出
    output reg        sdata_o    // 模型串行数据输出
);

reg [15:0] sample_mem [0:7]; // 8 路模拟采样缓存，用来按通道输出测试数据

integer sample_id;           // 当前是第几次采样，用于生成变化的测试样本
integer read_index;          // 当前正在输出的通道索引
integer bit_index;           // 当前正在输出的位索引
integer conv_token;          // 转换过程令牌，用于屏蔽旧转换分支的残留影响
integer i;                   // 预留的循环变量，当前版本未实际使用

// 根据 OS 设置返回对应的模拟转换时间
function integer conv_time_ns;
    input [2:0] os_sel;           // 传入的过采样模式选择值
    begin
        case (os_sel)
            3'd1: conv_time_ns = T_CONV_X2_NS;
            3'd2: conv_time_ns = T_CONV_X4_NS;
            3'd3: conv_time_ns = T_CONV_X8_NS;
            3'd4: conv_time_ns = T_CONV_X16_NS;
            3'd5: conv_time_ns = T_CONV_X32_NS;
            3'd6: conv_time_ns = T_CONV_X64_NS;
            default: conv_time_ns = T_CONV_NO_OS_NS;
        endcase
    end
endfunction

// 生成一组可观察的 8 通道测试样本，便于验证通道顺序和量程配置
task update_samples;
    input integer next_sample_id; // 下一次采样编号，用于构造变化的测试数据
    input        next_range;      // 下一次采样对应的量程选择
    integer      base;
    integer      idx;
    begin
        base = next_range ? 16'h2000 : 16'h1000;
        base = base + (next_sample_id << 8);
        for (idx = 0; idx < 8; idx = idx + 1) begin
            sample_mem[idx] = base + idx;
        end
    end
endtask

initial begin
    busy_o     = 1'b0;
    sdata_o    = 1'b0;
    sample_id  = 0;
    read_index = 0;
    bit_index  = 15;
    conv_token = 0;
    update_samples(0, 1'b0);
    sdata_o = sample_mem[0][15];
end

// 在复位拉高时恢复模型内部状态，并重新装载初始测试数据
always @(posedge reset_i) begin
    conv_token = conv_token + 1;
    busy_o     <= 1'b0;
    sample_id  <= 0;
    read_index <= 0;
    bit_index  <= 15;
    update_samples(0, range_i);
    sdata_o <= sample_mem[0][15];
end

// 在 CONVST 上升沿模拟一次 ADC 转换过程，并在转换结束后更新 8 路数据
always @(posedge convst_i) begin
    if (!reset_i && !busy_o) begin
        conv_token = conv_token + 1;
        busy_o <= 1'b1;
        fork
            begin : conv_proc
                integer my_token;
                integer next_sample_id;
                integer delay_ns;
                my_token = conv_token;
                next_sample_id = sample_id + 1;
                delay_ns = conv_time_ns(os_i);
                #(delay_ns);
                if ((my_token == conv_token) && !reset_i) begin
                    update_samples(next_sample_id, range_i);
                    sample_id  <= next_sample_id;
                    read_index <= 0;
                    bit_index  <= 15;
                    sdata_o    <= sample_mem[0][15];
                    busy_o     <= 1'b0;
                end
            end
        join_none
    end
end

// 当 CS 拉低时，从第 1 通道的 MSB 开始准备串行输出
always @(negedge cs_n_i) begin
    if (!busy_o) begin
        read_index <= 0;
        bit_index  <= 15;
        sdata_o    <= sample_mem[0][15];
    end
end

// 在 SCLK 下降沿把当前 bit 驱动到串行数据输出线上
always @(negedge sclk_i) begin
    if (!busy_o && !cs_n_i) begin
        sdata_o <= sample_mem[read_index][bit_index];
    end
end

// 在 SCLK 上升沿推进位计数，并在 16bit 读完后切到下一个通道
always @(posedge sclk_i) begin
    if (!busy_o && !cs_n_i) begin
        if (bit_index == 0) begin
            bit_index <= 15;
            if (read_index < 7) begin
                read_index <= read_index + 1;
            end
        end else begin
            bit_index <= bit_index - 1;
        end
    end
end

endmodule
