`timescale 1ns / 1ps

module AD7606_Parallel_DRIVER_tb;

reg         clk;
reg         rst_n;
reg         start;
reg         soft_reset;
wire        ad_busy;
wire        ad_frstdata;
wire [15:0] ad_data;
wire        ad_reset;
wire        ad_convst;
wire        ad_cs_n;
wire        ad_rd_n;
wire [3:0]  ad_channal;
wire [2:0]  ad_state;
wire [15:0] ch1_data;
wire [15:0] ch2_data;
wire [15:0] ch3_data;
wire [15:0] ch4_data;
wire [15:0] ch5_data;
wire [15:0] ch6_data;
wire [15:0] ch7_data;
wire [15:0] ch8_data;
wire [127:0] data_frame;
wire         data_valid;
wire         sample_active;
wire         timeout;

always #10 clk = ~clk;

task pulse_start;
begin
    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;
end
endtask

task wait_for_valid;
    integer cycle_count;
begin
    cycle_count = 0;
    while (!data_valid) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
        if (cycle_count > 2000) begin
            $display("TB FAIL: data_valid timeout");
            $finish;
        end
    end
end
endtask

task expect_frame;
    input [15:0] expected_base;
begin
    if (timeout !== 1'b0) begin
        $display("TB FAIL: timeout asserted");
        $finish;
    end

    if (ch1_data !== expected_base + 16'd0) begin
        $display("TB FAIL: ch1 mismatch, got=%h expected=%h", ch1_data, expected_base + 16'd0);
        $finish;
    end
    if (ch2_data !== expected_base + 16'd1) begin
        $display("TB FAIL: ch2 mismatch, got=%h expected=%h", ch2_data, expected_base + 16'd1);
        $finish;
    end
    if (ch3_data !== expected_base + 16'd2) begin
        $display("TB FAIL: ch3 mismatch, got=%h expected=%h", ch3_data, expected_base + 16'd2);
        $finish;
    end
    if (ch4_data !== expected_base + 16'd3) begin
        $display("TB FAIL: ch4 mismatch, got=%h expected=%h", ch4_data, expected_base + 16'd3);
        $finish;
    end
    if (ch5_data !== expected_base + 16'd4) begin
        $display("TB FAIL: ch5 mismatch, got=%h expected=%h", ch5_data, expected_base + 16'd4);
        $finish;
    end
    if (ch6_data !== expected_base + 16'd5) begin
        $display("TB FAIL: ch6 mismatch, got=%h expected=%h", ch6_data, expected_base + 16'd5);
        $finish;
    end
    if (ch7_data !== expected_base + 16'd6) begin
        $display("TB FAIL: ch7 mismatch, got=%h expected=%h", ch7_data, expected_base + 16'd6);
        $finish;
    end
    if (ch8_data !== expected_base + 16'd7) begin
        $display("TB FAIL: ch8 mismatch, got=%h expected=%h", ch8_data, expected_base + 16'd7);
        $finish;
    end

    if (data_frame[15:0] !== expected_base + 16'd0 ||
        data_frame[31:16] !== expected_base + 16'd1 ||
        data_frame[47:32] !== expected_base + 16'd2 ||
        data_frame[63:48] !== expected_base + 16'd3 ||
        data_frame[79:64] !== expected_base + 16'd4 ||
        data_frame[95:80] !== expected_base + 16'd5 ||
        data_frame[111:96] !== expected_base + 16'd6 ||
        data_frame[127:112] !== expected_base + 16'd7) begin
        $display("TB FAIL: data_frame mismatch");
        $finish;
    end
end
endtask

AD7606_Parallel_DRIVER #(
    .RESET_HIGH_CYCLES(4),
    .CONVST_LOW_CYCLES(2),
    .RD_LOW_CYCLES(2),
    .RD_HIGH_CYCLES(2),
    .BUSY_TIMEOUT_CYCLES(200)
) u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .soft_reset(soft_reset),
    .ad_busy(ad_busy),
    .ad_frstdata(ad_frstdata),
    .ad_data(ad_data),
    .ad_reset(ad_reset),
    .ad_convst(ad_convst),
    .ad_cs_n(ad_cs_n),
    .ad_rd_n(ad_rd_n),
    .ch1_data(ch1_data),
    .ch2_data(ch2_data),
    .ch3_data(ch3_data),
    .ch4_data(ch4_data),
    .ch5_data(ch5_data),
    .ch6_data(ch6_data),
    .ch7_data(ch7_data),
    .ch8_data(ch8_data),
    .data_frame(data_frame),
    .data_valid(data_valid),
    .sample_active(sample_active),
    .timeout(timeout),
    .ad_channal(ad_channal),
    .ad_state(ad_state)
);

ad7606_parallel_model #(
    .T_CONV_NO_OS_NS(200),
    .T_CONV_X2_NS(300),
    .T_CONV_X4_NS(400),
    .T_CONV_X8_NS(500),
    .T_CONV_X16_NS(600),
    .T_CONV_X32_NS(700),
    .T_CONV_X64_NS(800)
) u_model (
    .reset_i(ad_reset),
    .convst_i(ad_convst),
    .cs_n_i(ad_cs_n),
    .rd_n_i(ad_rd_n),
    .os_i(3'd0),
    .range_i(1'b1),
    .busy_o(ad_busy),
    .frstdata_o(ad_frstdata),
    .data_o(ad_data)
);

initial begin
    clk        = 1'b0;
    rst_n      = 1'b0;
    start      = 1'b0;
    soft_reset = 1'b0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;

    wait (sample_active == 1'b0);
    pulse_start;
    wait_for_valid;
    expect_frame(16'h2100);

    pulse_start;
    wait_for_valid;
    expect_frame(16'h2200);

    $display("TB PASS: AD7606_Parallel_DRIVER captured two frames correctly.");
    $finish;
end

endmodule
