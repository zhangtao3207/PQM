// Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
// Date        : Thu Apr 16 22:23:35 2026
// Host        : DESKTOP-6DUCG5H running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               c:/Users/zhangtao/Desktop/PQM/FPGA/prj/PQM.srcs/sources_1/ip/rom_atan_lut_1024/rom_atan_lut_1024_stub.v
// Design      : rom_atan_lut_1024
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z020clg400-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_2,Vivado 2018.3" *)
module rom_atan_lut_1024(clka, ena, addra, douta)
/* synthesis syn_black_box black_box_pad_pin="clka,ena,addra[10:0],douta[13:0]" */;
  input clka;
  input ena;
  input [10:0]addra;
  output [13:0]douta;
endmodule
