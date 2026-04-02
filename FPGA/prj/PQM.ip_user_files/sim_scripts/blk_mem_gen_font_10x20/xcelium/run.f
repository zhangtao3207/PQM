-makelib xcelium_lib/xil_defaultlib -sv \
  "D:/zt/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "D:/zt/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
-endlib
-makelib xcelium_lib/xpm \
  "D:/zt/Xilinx/Vivado/2018.3/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib xcelium_lib/blk_mem_gen_v8_4_2 \
  "../../../ipstatic/simulation/blk_mem_gen_v8_4.v" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  "../../../../PQM.srcs/sources_1/ip/blk_mem_gen_font_10x20/sim/blk_mem_gen_font_10x20.v" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  glbl.v
-endlib

