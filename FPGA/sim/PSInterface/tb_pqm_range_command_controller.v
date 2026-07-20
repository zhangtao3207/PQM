`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_range_command_controller
 * 功能: 验证 PS 量程命令的确认响应、非法命令拒绝和量程状态保持。
 * 输入: 无。
 * 输出: 无。
 * 双向: 无。
 */
module tb_pqm_range_command_controller;

localparam [31:0] COMMAND_SET_RANGE = 32'h0000_0001;
localparam [31:0] RESPONSE_ERROR = 32'hFFFF_FFFF;

reg         clk;
reg         rst_n;
reg         command_valid;
reg  [31:0] command_code;
reg  [31:0] command_argument;
reg         response_ready;
wire        response_valid;
wire [31:0] response;
wire        low_range_active;

// 生成 50 MHz 仿真时钟。
always #10 clk = ~clk;

// 实例化待测量程命令控制器。
pqm_range_command_controller dut (
    .clk(clk),
    .rst_n(rst_n),
    .command_valid(command_valid),
    .command_code(command_code),
    .command_argument(command_argument),
    .response_valid(response_valid),
    .response_ready(response_ready),
    .response(response),
    .low_range_active(low_range_active)
);

// 发出单拍命令，并在下一拍检查控制器响应。
task issue_command;
    input [31:0] code;
    input [31:0] argument;
    begin
        @(negedge clk);
        command_code = code;
        command_argument = argument;
        command_valid = 1'b1;
        @(negedge clk);
        command_valid = 1'b0;
    end
endtask

// 对关键状态做硬断言，失败时立即终止仿真。
task check_equal;
    input [31:0] actual;
    input [31:0] expected;
    input [8*64-1:0] message;
    begin
        if (actual !== expected) begin
            $display("FAIL: %0s actual=%h expected=%h", message,
                     actual, expected);
            $finish;
        end
    end
endtask

// 依次覆盖有效切换、背压保持和非法请求。
initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    command_valid = 1'b0;
    command_code = 32'd0;
    command_argument = 32'd0;
    response_ready = 1'b0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    check_equal(low_range_active, 32'd0, "reset selects high range");

    issue_command(COMMAND_SET_RANGE, 32'd1);
    check_equal(response_valid, 32'd1, "low range response valid");
    check_equal(response, 32'd1, "low range response echoes state");
    check_equal(low_range_active, 32'd1, "low range applied");
    repeat (2) @(negedge clk);
    check_equal(response_valid, 32'd1, "response held under backpressure");
    response_ready = 1'b1;
    @(negedge clk);
    response_ready = 1'b0;
    check_equal(response_valid, 32'd0, "response clears after handshake");

    issue_command(COMMAND_SET_RANGE, 32'd2);
    check_equal(response, RESPONSE_ERROR, "invalid argument rejected");
    check_equal(low_range_active, 32'd1, "invalid argument preserves range");
    response_ready = 1'b1;
    @(negedge clk);
    response_ready = 1'b0;

    issue_command(32'h1234_5678, 32'd0);
    check_equal(response, RESPONSE_ERROR, "unknown command rejected");
    check_equal(low_range_active, 32'd1, "unknown command preserves range");
    response_ready = 1'b1;
    @(negedge clk);
    response_ready = 1'b0;

    issue_command(COMMAND_SET_RANGE, 32'd0);
    check_equal(response, 32'd0, "high range response echoes state");
    check_equal(low_range_active, 32'd0, "high range applied");

    $display("PASS: pqm_range_command_controller");
    $finish;
end

endmodule
