# Copyright (C) 1991-2013 Altera Corporation
# Your use of Altera Corporation's design tools, logic functions 
# and other software and tools, and its AMPP partner logic 
# functions, and any output files from any of the foregoing 
# (including device programming or simulation files), and any 
# associated documentation or information are expressly subject 
# to the terms and conditions of the Altera Program License 
# Subscription Agreement, Altera MegaCore Function License 
# Agreement, or other applicable license agreement, including, 
# without limitation, that your use is for the sole purpose of 
# programming logic devices manufactured by Altera and sold by 
# Altera or its authorized distributors.  Please refer to the 
# applicable agreement for further details.

# Quartus II 64-Bit Version 13.0.0 Build 156 04/24/2013 SJ Full Version
# File: C:\Users\Administrator\Desktop\ac620_ad7606_uart\prj\AC620_AD7606_UART.tcl
# Generated on: Tue May 23 21:33:57 2023

package require ::quartus::project

set_location_assignment PIN_K2 -to ad7606_busy_i
set_location_assignment PIN_N2 -to ad7606_convst_o
set_location_assignment PIN_K1 -to ad7606_cs_n_o
set_location_assignment PIN_D3 -to ad7606_db_i[15]
set_location_assignment PIN_E5 -to ad7606_db_i[14]
set_location_assignment PIN_D1 -to ad7606_db_i[13]
set_location_assignment PIN_F1 -to ad7606_db_i[12]
set_location_assignment PIN_F5 -to ad7606_db_i[11]
set_location_assignment PIN_F2 -to ad7606_db_i[10]
set_location_assignment PIN_G2 -to ad7606_db_i[9]
set_location_assignment PIN_G1 -to ad7606_db_i[8]
set_location_assignment PIN_F3 -to ad7606_db_i[7]
set_location_assignment PIN_G5 -to ad7606_db_i[6]
set_location_assignment PIN_J6 -to ad7606_db_i[5]
set_location_assignment PIN_K5 -to ad7606_db_i[4]
set_location_assignment PIN_L4 -to ad7606_db_i[3]
set_location_assignment PIN_K6 -to ad7606_db_i[2]
set_location_assignment PIN_L3 -to ad7606_db_i[1]
set_location_assignment PIN_L6 -to ad7606_db_i[0]
set_location_assignment PIN_N1 -to ad7606_os_o[2]
set_location_assignment PIN_R1 -to ad7606_os_o[1]
set_location_assignment PIN_P2 -to ad7606_os_o[0]
set_location_assignment PIN_L2 -to ad7606_rd_n_o
set_location_assignment PIN_L1 -to ad7606_reset_o
set_location_assignment PIN_E1 -to Clk
set_location_assignment PIN_M16 -to Reset_n
set_location_assignment PIN_A6 -to Rs232_Tx
set_location_assignment PIN_B5 -to Rs232_Rx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to Clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to Reset_n
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to Rs232_Rx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to Rs232_Tx
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_busy_i
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_convst_o
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_cs_n_o
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[15]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[14]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[13]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[12]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[11]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[10]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[9]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[8]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_db_i[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_os_o[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_os_o[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_os_o[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_rd_n_o
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ad7606_reset_o
