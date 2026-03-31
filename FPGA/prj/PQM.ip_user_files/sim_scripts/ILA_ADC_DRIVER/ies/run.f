-makelib ies_lib/xil_defaultlib -sv \
  "D:/zt/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "D:/zt/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
-endlib
-makelib ies_lib/xpm \
  "D:/zt/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib ies_lib/xil_defaultlib \
  "../../../../PQM.srcs/sources_1/ip/ILA_ADC_DRIVER/sim/ILA_ADC_DRIVER.v" \
-endlib
-makelib ies_lib/xil_defaultlib \
  glbl.v
-endlib

