`timescale 1ns/1ns

module uart_cmd(
    Clk,
    Reset_n,
    rx_data,
    rx_done,
    address,
    data,
    cmdvalid
);
    
    input Clk;
    input Reset_n;
    input [7:0]rx_data;
    input rx_done;
    output reg[7:0]address;
    output reg[31:0]data;
    output reg cmdvalid;
    
    reg [7:0] data_str [7:0];
    always@(posedge Clk)
    if(rx_done)begin
        data_str[7] <= #1 rx_data;
        data_str[6] <= #1 data_str[7];
        data_str[5] <= #1 data_str[6];
        data_str[4] <= #1 data_str[5];
        data_str[3] <= #1 data_str[4];
        data_str[2] <= #1 data_str[3];
        data_str[1] <= #1 data_str[2];
        data_str[0] <= #1 data_str[1];        
    end
    
    reg r_rx_done;
    always@(posedge Clk)
        r_rx_done <= rx_done;
    
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n) begin
        address <= #1 0;
        data <= #1 0;
        cmdvalid <= #1 0;
    end else if(r_rx_done)begin
        if((data_str[0] == 8'h55) && (data_str[1] == 8'hA5) && (data_str[7] == 8'hF0))begin
            data[7:0] <= #1 data_str[6];
            data[15:8] <= #1 data_str[5];
            data[23:16] <= #1 data_str[4];
            data[31:24] <= #1 data_str[3];
            address <= #1 data_str[2];
            cmdvalid <= #1 1;
        end
    end
    else
        cmdvalid <= #1 0;     
    
endmodule
