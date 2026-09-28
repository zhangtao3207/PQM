# ============================================================================
# PQM2 测量版顶层（pqm2_meas_top）引脚与时序约束。
#
# 来源：
#   LCD / 触摸 EMIO 部分与 vivado/constrs/official_lcd.xdc 逐条一致（同一块板）。
#   sys_clk / sys_rst_n / AD7606 取自只读参考工程
#   C:\Users\zhangtao\Desktop\PQM\FPGA\data\PQM.xdc 中**未被注释**的那一段
#   （该文件里另有一段被注释掉的旧 AD7606 块，含 Convst_A/Convst_B，不使用）。
# ============================================================================

# ---------------------- 时钟与复位 ----------------------
# 板载 50 MHz 晶振 U18 -> clk_wiz_0 -> clk_out1 = 50 MHz 测量链时钟
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]

# ---------------------- AD7606 并行 ADC ----------------------
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports OS1]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports OS0]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports OS2]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports Convst]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports RD]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports RESET]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports Busy]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports cs]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports Frstdata]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports Range]
set_property PULLDOWN true [get_ports Frstdata]

set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports DB0]
set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports DB1]
set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports DB2]
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS33} [get_ports DB3]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports DB4]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports DB5]
set_property -dict {PACKAGE_PIN W9  IOSTANDARD LVCMOS33} [get_ports DB6]
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports DB7]
set_property -dict {PACKAGE_PIN Y8  IOSTANDARD LVCMOS33} [get_ports DB8]
set_property -dict {PACKAGE_PIN Y9  IOSTANDARD LVCMOS33} [get_ports DB9]
set_property -dict {PACKAGE_PIN Y6  IOSTANDARD LVCMOS33} [get_ports DB10]
set_property -dict {PACKAGE_PIN Y7  IOSTANDARD LVCMOS33} [get_ports DB11]
set_property -dict {PACKAGE_PIN V6  IOSTANDARD LVCMOS33} [get_ports DB12]
set_property -dict {PACKAGE_PIN W6  IOSTANDARD LVCMOS33} [get_ports DB13]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports DB14]
set_property -dict {PACKAGE_PIN U10 IOSTANDARD LVCMOS33} [get_ports DB15]

# ---------------------- LCD ----------------------
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[0]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[1]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[3]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[4]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[5]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[6]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[7]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[8]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[9]}]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[10]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[11]}]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[12]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[13]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[14]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[15]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[16]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[17]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[18]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[19]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[20]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[21]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[22]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb_tri_io[23]}]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports lcd_hs]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports lcd_vs]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports lcd_de]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports lcd_bl]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports lcd_clk]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports lcd_rst]

# ---------------------- 触摸（PS EMIO GPIO） ----------------------
# lcd_scl
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports {GPIO_EMIO_tri_io[0]}]
# lcd_sda
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports {GPIO_EMIO_tri_io[1]}]
# CT_RST
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {GPIO_EMIO_tri_io[2]}]
# CT_INT
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {GPIO_EMIO_tri_io[3]}]
