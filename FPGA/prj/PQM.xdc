#时序约束
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]

#IO管脚约束
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]

#UART约束
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports uart_txd]

#LCD显示驱动约束
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[0]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[1]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[3]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[4]}]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[5]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[6]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[7]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[8]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[9]}]
set_property -dict {PACKAGE_PIN T17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[10]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[11]}]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[12]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[13]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[14]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[15]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[16]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[17]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[18]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[19]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[20]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[21]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[22]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {lcd_rgb[23]}]

set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports lcd_hs]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports lcd_vs]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports lcd_de]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports lcd_bl]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports lcd_clk]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports lcd_rst_n]

#LCD触摸屏驱动约束
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports touch_scl]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports touch_sda]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports touch_int]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports touch_rst_n]




# set_property IOSTANDARD LVCMOS33 [get_ports ad_convst]
# set_property PACKAGE_PIN T11 [get_ports ad_convst]
# set_property IOSTANDARD LVCMOS33 [get_ports ad_rst]
# set_property PACKAGE_PIN V5 [get_ports ad_rst]
# set_property IOSTANDARD LVCMOS33 [get_ports ad_rd_n]
# set_property PACKAGE_PIN T5 [get_ports ad_rd_n]
# set_property IOSTANDARD LVCMOS33 [get_ports ad_cs_n]
# set_property PACKAGE_PIN U5 [get_ports ad_cs_n]
# set_property IOSTANDARD LVCMOS33 [get_ports ad_busy]
# set_property PACKAGE_PIN U7 [get_ports ad_busy]
# set_property IOSTANDARD LVCMOS33 [get_ports ad_frstdata]
# set_property PACKAGE_PIN V7 [get_ports ad_frstdata]
# set_property PULLDOWN true [get_ports ad_frstdata]

# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[0]}]
# set_property PACKAGE_PIN U8 [get_ports {ad_data[0]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[1]}]
# set_property PACKAGE_PIN U9 [get_ports {ad_data[1]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[2]}]
# set_property PACKAGE_PIN T9 [get_ports {ad_data[2]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[3]}]
# set_property PACKAGE_PIN U10 [get_ports {ad_data[3]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[4]}]
# set_property PACKAGE_PIN V6 [get_ports {ad_data[4]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[5]}]
# set_property PACKAGE_PIN W6 [get_ports {ad_data[5]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[6]}]
# set_property PACKAGE_PIN Y6 [get_ports {ad_data[6]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[7]}]
# set_property PACKAGE_PIN Y7 [get_ports {ad_data[7]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[8]}]
# set_property PACKAGE_PIN Y8 [get_ports {ad_data[8]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[9]}]
# set_property PACKAGE_PIN Y9 [get_ports {ad_data[9]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[10]}]
# set_property PACKAGE_PIN W9 [get_ports {ad_data[10]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[11]}]
# set_property PACKAGE_PIN W10 [get_ports {ad_data[11]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[12]}]
# set_property PACKAGE_PIN V10 [get_ports {ad_data[12]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[13]}]
# set_property PACKAGE_PIN V11 [get_ports {ad_data[13]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[14]}]
# set_property PACKAGE_PIN Y12 [get_ports {ad_data[14]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {ad_data[15]}]
# set_property PACKAGE_PIN Y13 [get_ports {ad_data[15]}]

#------------------------------------------------------------------------------
# ADC_TEMP / 原数字电压表示例 8bit ADC 约束模板
# 说明：
# 1. 这组约束对应 adc_abs_voltage_top 的端口命名：
#    sys_clk / sys_rst_n / ad_data[7:0] / ad_clk / ad_otr
# 2. 当前工程顶层 main.v 还没有把 ad_clk / ad_otr / ad_data[7:0] 正式作为顶层端口启用，
#    因此这里先保留为注释模板，避免当前工程综合时报 “port not found”。
# 3. 当你把这些端口接入当前工程最终顶层后，直接取消下面对应行的注释即可。
#------------------------------------------------------------------------------

set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U14} [get_ports {ad_data[7]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U15} [get_ports {ad_data[6]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V12} [get_ports {ad_data[5]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W13} [get_ports {ad_data[4]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W14} [get_ports {ad_data[3]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y14} [get_ports {ad_data[2]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V15} [get_ports {ad_data[1]}]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W15} [get_ports {ad_data[0]}]

set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V13} [get_ports ad_clk]
set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U13} [get_ports ad_otr]
