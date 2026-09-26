`timescale 1ns / 1ps

/*
 * 模块: rom_atan_lut_1024（仿真模型，不参与综合）
 * 功能:
 *   Vivado Block Memory Generator 生成的 rom_atan_lut_1024 的行为级等价模型，
 *   供 xsim 单元仿真使用；不要把它加进综合源集。
 *
 * 与真实 IP 的参数对齐（取自旧工程 ip/rom_atan_lut_1024/rom_atan_lut_1024.xci）：
 *   深度 1025、位宽 14、单端口 ROM、Port A 使用 ENA 引脚、读延迟 1 拍。
 *   因此地址 1024 是合法地址（内容是 90.00 度对应的 9000），不是越界。
 *
 * 初始化数据来自 pl/sim/models/atan_lut_1024.mem，该文件由旧工程
 * data/atan_lut_1024.coe 经 pl/scripts/coe_to_mem.ps1 机械转换得到（同一份 COE
 * 就是真实 IP 的初始值来源），因此内容与真实 ROM 一致。
 *
 * 运行要求：.mem 文件必须位于仿真工作目录下（scripts/run_xsim.ps1 会把
 * pl/sim/models/ 下的数据文件复制到每个用例的 build 目录）。
 */

module rom_atan_lut_1024 (
    input  wire        clka,
    input  wire        ena,
    input  wire [10:0] addra,
    output reg  [13:0] douta
);

    reg [13:0] mem [0:1024];

    initial begin
        $readmemh("atan_lut_1024.mem", mem);
    end

    // 读延迟 1 拍：ena 有效时在时钟沿把 mem[addra] 送到 douta，ena 无效时保持。
    always @(posedge clka) begin
        if (ena)
            douta <= mem[addra];
    end

endmodule
