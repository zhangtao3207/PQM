`timescale 1ns / 1ps

//==============================================================================
// Module Name: ad7606_parallel_model
// Function:
//   CM2248/AD7606 并行接口简化行为模型，用于验证并行控制器读数时序。
//   模型行为包括：
//   1. 在收到 CONVST 后拉高 BUSY，并等待对应转换时间；
//   2. 转换结束后生成 8 路可预测样本数据；
//   3. 在 CS# / RD# 时序下依次输出 8 路并行数据；
//   4. 在读取第 1 路 V1 数据期间输出 FRSTDATA=1。
//==============================================================================
module ad7606_parallel_model #(
    parameter integer T_CONV_NO_OS_NS = 4000,
    parameter integer T_CONV_X2_NS    = 8700,
    parameter integer T_CONV_X4_NS    = 16000,
    parameter integer T_CONV_X8_NS    = 31000,
    parameter integer T_CONV_X16_NS   = 62000,
    parameter integer T_CONV_X32_NS   = 123000,
    parameter integer T_CONV_X64_NS   = 286000
)(
    input  wire       reset_i,
    input  wire       convst_i,
    input  wire       cs_n_i,
    input  wire       rd_n_i,
    input  wire [2:0] os_i,
    input  wire       range_i,
    output reg        busy_o,
    output reg        frstdata_o,
    output reg [15:0] data_o
);

reg [15:0] sample_mem [0:7];  // 8 路样本存储器
integer sample_id;            // 当前采样帧编号
integer read_index;           // 当前读取通道索引
integer conv_token;           // 转换事务令牌，用于屏蔽过期延时线程

// 根据 OS 选择本次转换耗时。
function integer conv_time_ns;
    input [2:0] os_sel;
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

// 生成一帧可预测数据，便于 testbench 校验。
task update_samples;
    input integer next_sample_id;
    input         next_range;
    integer       base;
    integer       idx;
    begin
        base = next_range ? 16'h2000 : 16'h1000;
        base = base + (next_sample_id << 8);
        for (idx = 0; idx < 8; idx = idx + 1)
            sample_mem[idx] = base + idx;
    end
endtask

// 仿真初始值。
initial begin
    busy_o     = 1'b0;
    frstdata_o = 1'b0;
    data_o     = 16'd0;
    sample_id  = 0;
    read_index = 0;
    conv_token = 0;
    update_samples(0, 1'b0);
    data_o = sample_mem[0];
end

// 复位时清空状态并重新生成初始样本。
always @(posedge reset_i) begin
    conv_token = conv_token + 1;
    busy_o     <= 1'b0;
    frstdata_o <= 1'b0;
    data_o     <= 16'd0;
    sample_id  <= 0;
    read_index <= 0;
    update_samples(0, range_i);
    data_o <= sample_mem[0];
end

// CONVST 上升沿触发一次转换。
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
                    frstdata_o <= 1'b0;
                    data_o     <= sample_mem[0];
                    busy_o     <= 1'b0;
                end
            end
        join
    end
end

// CS# 下降沿重新对齐到第 1 路读取。
always @(negedge cs_n_i) begin
    if (!busy_o) begin
        read_index <= 0;
        frstdata_o <= 1'b0;
        data_o <= sample_mem[0];
    end
end

// CS# 上升沿后 FRSTDATA 回到空闲低电平。
always @(posedge cs_n_i) begin
    frstdata_o <= 1'b0;
end

// RD# 下降沿时，把当前通道数据送上总线；第 1 路时拉高 FRSTDATA。
always @(negedge rd_n_i) begin
    if (!busy_o && !cs_n_i) begin
        frstdata_o <= (read_index == 0);
        data_o <= sample_mem[read_index];
    end
end

// RD# 上升沿时准备下一通道数据索引。
always @(posedge rd_n_i) begin
    if (!busy_o && !cs_n_i && (read_index < 7))
        read_index <= read_index + 1;
end

endmodule
