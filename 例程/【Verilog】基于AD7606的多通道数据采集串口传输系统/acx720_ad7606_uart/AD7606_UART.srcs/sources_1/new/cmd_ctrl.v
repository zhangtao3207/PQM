`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2021/02/25 11:09:38
// Design Name: 
// Module Name: cmd_ctrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cmd_ctrl(
    Clk,
    Reset_n,
    cmd_data,
    cmd_addr,
    cmdvalid,
    RestartReq,
    ChannelSel,
    DataNum,
    ADC_Speed_Set
        );
    input Clk;        
    input Reset_n;  
    input [31:0]cmd_data;
    input [7:0]cmd_addr;
    input cmdvalid;
    
     output reg RestartReq;
     output reg [7:0] ChannelSel; 
     output reg [14:0]DataNum;    
     output reg [24:0]ADC_Speed_Set;
     
         always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)begin
        ChannelSel <= 8'b1111_1111;
        DataNum <= 16'd32;
        ADC_Speed_Set <= 32'd9999;
        RestartReq <= 1'b0;
    end
    else if(cmdvalid)begin
        case(cmd_addr)
            0: RestartReq <= 1'b1;
            1: ChannelSel <= cmd_data[7:0];
            2: DataNum <= cmd_data[15:0];
            3: ADC_Speed_Set <= cmd_data;
            4: 
                begin
                    ChannelSel <= cmd_data[7:0];
                    DataNum <= cmd_data[23:8];
                    RestartReq <= 1'b1;
                end
          default:;
      endcase    
    end
    else
        RestartReq <= 1'b0;
    
    
    
    
    
    
    
    
endmodule
