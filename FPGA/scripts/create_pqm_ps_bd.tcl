# Create the PQM Zynq PS block design in the currently open Vivado project.
set bd_name pqm_ps

proc externalize_intf {pin new_name} {
    set generated_name "[get_property NAME $pin]_0"
    make_bd_intf_pins_external $pin
    set port [get_bd_intf_ports -quiet $generated_name]
    if {[llength $port] != 1} {
        error "Failed to externalize interface [get_property NAME $pin]"
    }
    set_property name $new_name $port
}

if {[llength [get_bd_designs -quiet $bd_name]] != 0} {
    close_bd_design [get_bd_designs $bd_name]
    remove_files [get_files -quiet */${bd_name}.bd]
}

create_bd_design $bd_name
current_bd_design $bd_name

# Processing system: ZYNQ-7020, 1 GiB/32-bit DDR3, board MIO and EMIO services.
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666667} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_I2C0_I2C0_IO {EMIO} \
    CONFIG.PCW_GPIO_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {0} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {3} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} \
    CONFIG.PCW_S_AXI_HP1_DATA_WIDTH {64} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_IRQ_F2P_MODE {REVERSE} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
] $ps

externalize_intf [get_bd_intf_pins $ps/DDR] DDR
externalize_intf [get_bd_intf_pins $ps/FIXED_IO] FIXED_IO

if {[llength [get_bd_intf_pins -quiet $ps/IIC_0]] == 1} {
    externalize_intf [get_bd_intf_pins $ps/IIC_0] TOUCH_IIC
}
if {[llength [get_bd_intf_pins -quiet $ps/GPIO_0]] == 1} {
    externalize_intf [get_bd_intf_pins $ps/GPIO_0] TOUCH_GPIO
}

# AXI control plane and dedicated DDR data planes.
set axi_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_ctrl]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {3}] $axi_ctrl

set axi_hp0 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_hp0]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $axi_hp0

set axi_hp1 [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_hp1]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $axi_hp1

set bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_0]
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SINGLE_PORT_BRAM {1}] $bram_ctrl

set shared_bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_shared]
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Write_Depth_A {16384} \
    CONFIG.Write_Width_B {32} \
    CONFIG.Read_Width_B {32} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Use_Byte_Write_Enable {true} \
    CONFIG.Byte_Size {8} \
] $shared_bram

set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_sg {1} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_sg_length_width {23} \
] $dma

# The register slice owns the PL-facing 64-bit stream width and propagates it to AXI DMA.
set sample_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_register_slice:1.1 axis_sample_slice]
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {8} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.REG_CONFIG {1} \
] $sample_slice

set sample_cdc [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_clock_converter:1.1 axis_sample_cdc]
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES {8} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
] $sample_cdc

set vdma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0]
set_property -dict [list \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {16} \
    CONFIG.c_mm2s_max_burst_length {16} \
    CONFIG.c_num_fstores {2} \
    CONFIG.c_include_mm2s_dre {1} \
    CONFIG.c_use_fsync {1} \
    CONFIG.c_use_mm2s_fsync {1} \
] $vdma

connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $axi_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_ctrl/M00_AXI] [get_bd_intf_pins $bram_ctrl/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_ctrl/M01_AXI] [get_bd_intf_pins $dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins $axi_ctrl/M02_AXI] [get_bd_intf_pins $vdma/S_AXI_LITE]

connect_bd_intf_net [get_bd_intf_pins $bram_ctrl/BRAM_PORTA] [get_bd_intf_pins $shared_bram/BRAM_PORTA]
externalize_intf [get_bd_intf_pins $shared_bram/BRAM_PORTB] PL_SHARED_BRAM

connect_bd_intf_net [get_bd_intf_pins $vdma/M_AXI_MM2S] [get_bd_intf_pins $axi_hp0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_hp0/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP0]

connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_S2MM] [get_bd_intf_pins $axi_hp1/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $dma/M_AXI_SG] [get_bd_intf_pins $axi_hp1/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_hp1/M00_AXI] [get_bd_intf_pins $ps/S_AXI_HP1]

connect_bd_intf_net [get_bd_intf_pins $sample_slice/M_AXIS] [get_bd_intf_pins $dma/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins $sample_cdc/M_AXIS] [get_bd_intf_pins $sample_slice/S_AXIS]
externalize_intf [get_bd_intf_pins $sample_cdc/S_AXIS] S_AXIS_SAMPLES
externalize_intf [get_bd_intf_pins $vdma/M_AXIS_MM2S] M_AXIS_VIDEO_RGB565
set_property CONFIG.FREQ_HZ {50000000} [get_bd_intf_ports S_AXIS_SAMPLES]
set_property CONFIG.FREQ_HZ {25000000} [get_bd_intf_ports M_AXIS_VIDEO_RGB565]

# Pixel clock, 800x480 timing and native RGB888 video output.
set clk_pixel [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_pixel]
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.USE_RESET {true} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
] $clk_pixel

set vtc [create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.1 v_tc_0]
set_property -dict [list \
    CONFIG.VIDEO_MODE {Custom} \
    CONFIG.enable_detection {false} \
    CONFIG.enable_generation {true} \
    CONFIG.GEN_HACTIVE_SIZE {800} \
    CONFIG.GEN_HFRAME_SIZE {1056} \
    CONFIG.GEN_HSYNC_START {840} \
    CONFIG.GEN_HSYNC_END {968} \
    CONFIG.GEN_VACTIVE_SIZE {480} \
    CONFIG.GEN_F0_VFRAME_SIZE {525} \
    CONFIG.GEN_F0_VSYNC_VSTART {490} \
    CONFIG.GEN_F0_VSYNC_VEND {492} \
    CONFIG.GEN_F0_VBLANK_HSTART {800} \
    CONFIG.GEN_F0_VBLANK_HEND {800} \
    CONFIG.GEN_F0_VSYNC_HSTART {840} \
    CONFIG.GEN_F0_VSYNC_HEND {840} \
    CONFIG.GEN_HSYNC_POLARITY {Low} \
    CONFIG.GEN_VSYNC_POLARITY {Low} \
    CONFIG.GEN_AVIDEO_POLARITY {High} \
] $vtc

set video_out [create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0]
set_property -dict [list \
    CONFIG.C_HAS_ASYNC_CLK {0} \
    CONFIG.C_S_AXIS_VIDEO_FORMAT {2} \
    CONFIG.C_S_AXIS_VIDEO_DATA_WIDTH {8} \
] $video_out

connect_bd_intf_net [get_bd_intf_pins $vtc/vtiming_out] [get_bd_intf_pins $video_out/vtiming_in]
externalize_intf [get_bd_intf_pins $video_out/video_in] S_AXIS_VIDEO_RGB888
externalize_intf [get_bd_intf_pins $video_out/vid_io_out] LCD_VIDEO
set_property CONFIG.FREQ_HZ {25000000} [get_bd_intf_ports S_AXIS_VIDEO_RGB888]

# Clock and reset distribution.
set rst_axi [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_fclk0]
set rst_vid [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_pixel]
set reset_not [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 invert_fclk_reset]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $reset_not

set logic_one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_logic1]
set_property CONFIG.CONST_VAL {1} $logic_one
set logic_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_logic0]
set_property CONFIG.CONST_VAL {0} $logic_zero

connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
    [get_bd_pins $ps/M_AXI_GP0_ACLK] \
    [get_bd_pins $ps/S_AXI_HP0_ACLK] \
    [get_bd_pins $ps/S_AXI_HP1_ACLK] \
    [get_bd_pins $axi_ctrl/ACLK] [get_bd_pins $axi_ctrl/S00_ACLK] \
    [get_bd_pins $axi_ctrl/M00_ACLK] [get_bd_pins $axi_ctrl/M01_ACLK] [get_bd_pins $axi_ctrl/M02_ACLK] \
    [get_bd_pins $axi_hp0/ACLK] [get_bd_pins $axi_hp0/S00_ACLK] [get_bd_pins $axi_hp0/M00_ACLK] \
    [get_bd_pins $axi_hp1/ACLK] [get_bd_pins $axi_hp1/S00_ACLK] [get_bd_pins $axi_hp1/S01_ACLK] [get_bd_pins $axi_hp1/M00_ACLK] \
    [get_bd_pins $bram_ctrl/s_axi_aclk] \
    [get_bd_pins $dma/s_axi_lite_aclk] [get_bd_pins $dma/m_axi_s2mm_aclk] [get_bd_pins $dma/m_axi_sg_aclk] \
    [get_bd_pins $sample_slice/aclk] \
    [get_bd_pins $sample_cdc/m_axis_aclk] \
    [get_bd_pins $vdma/s_axi_lite_aclk] [get_bd_pins $vdma/m_axi_mm2s_aclk] \
    [get_bd_pins $vtc/s_axi_aclk] \
    [get_bd_pins $clk_pixel/clk_in1] [get_bd_pins $rst_axi/slowest_sync_clk]

connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $reset_not/Op1]
connect_bd_net [get_bd_pins $reset_not/Res] [get_bd_pins $rst_axi/ext_reset_in] [get_bd_pins $rst_vid/ext_reset_in]
connect_bd_net [get_bd_pins $logic_one/dout] [get_bd_pins $rst_axi/dcm_locked]
connect_bd_net [get_bd_pins $logic_zero/dout] \
    [get_bd_pins $rst_axi/aux_reset_in] [get_bd_pins $rst_axi/mb_debug_sys_rst] \
    [get_bd_pins $rst_vid/aux_reset_in] [get_bd_pins $rst_vid/mb_debug_sys_rst]
connect_bd_net [get_bd_pins $rst_axi/peripheral_reset] [get_bd_pins $clk_pixel/reset]
connect_bd_net [get_bd_pins $clk_pixel/clk_out1] \
    [get_bd_pins $rst_vid/slowest_sync_clk] \
    [get_bd_pins $vdma/m_axis_mm2s_aclk] \
    [get_bd_pins $vtc/clk] [get_bd_pins $video_out/aclk]
connect_bd_net [get_bd_pins $clk_pixel/locked] [get_bd_pins $rst_vid/dcm_locked]

set pl_axi_clk [create_bd_port -dir O -type clk PL_AXI_CLK]
set_property CONFIG.FREQ_HZ {100000000} $pl_axi_clk
connect_bd_net [get_bd_pins $ps/FCLK_CLK0] $pl_axi_clk
set pl_axi_resetn [create_bd_port -dir O -type rst PL_AXI_ARESETN]
connect_bd_net [get_bd_pins $rst_axi/peripheral_aresetn] $pl_axi_resetn

set pixel_clk [create_bd_port -dir O -type clk PIXEL_CLK]
set_property -dict [list CONFIG.FREQ_HZ {25000000} CONFIG.ASSOCIATED_BUSIF {M_AXIS_VIDEO_RGB565:S_AXIS_VIDEO_RGB888}] $pixel_clk
connect_bd_net [get_bd_pins $clk_pixel/clk_out1] $pixel_clk
set pixel_resetn [create_bd_port -dir O -type rst PIXEL_ARESETN]
connect_bd_net [get_bd_pins $rst_vid/peripheral_aresetn] $pixel_resetn

set sample_axis_clk [create_bd_port -dir I -type clk SAMPLE_AXIS_CLK]
set_property -dict [list CONFIG.FREQ_HZ {50000000} CONFIG.ASSOCIATED_BUSIF {S_AXIS_SAMPLES}] $sample_axis_clk
connect_bd_net $sample_axis_clk [get_bd_pins $sample_cdc/s_axis_aclk]
set sample_axis_resetn [create_bd_port -dir I -type rst SAMPLE_AXIS_ARESETN]
connect_bd_net $sample_axis_resetn [get_bd_pins $sample_cdc/s_axis_aresetn]

connect_bd_net [get_bd_pins $rst_axi/interconnect_aresetn] \
    [get_bd_pins $axi_ctrl/ARESETN] [get_bd_pins $axi_ctrl/S00_ARESETN] \
    [get_bd_pins $axi_ctrl/M00_ARESETN] [get_bd_pins $axi_ctrl/M01_ARESETN] [get_bd_pins $axi_ctrl/M02_ARESETN] \
    [get_bd_pins $axi_hp0/ARESETN] [get_bd_pins $axi_hp0/S00_ARESETN] [get_bd_pins $axi_hp0/M00_ARESETN] \
    [get_bd_pins $axi_hp1/ARESETN] [get_bd_pins $axi_hp1/S00_ARESETN] [get_bd_pins $axi_hp1/S01_ARESETN] [get_bd_pins $axi_hp1/M00_ARESETN]
connect_bd_net [get_bd_pins $rst_axi/peripheral_aresetn] \
    [get_bd_pins $bram_ctrl/s_axi_aresetn] [get_bd_pins $dma/axi_resetn] [get_bd_pins $vdma/axi_resetn] \
    [get_bd_pins $sample_slice/aresetn] [get_bd_pins $sample_cdc/m_axis_aresetn] [get_bd_pins $vtc/s_axi_aresetn]
connect_bd_net [get_bd_pins $rst_vid/peripheral_aresetn] [get_bd_pins $vtc/resetn] [get_bd_pins $video_out/aresetn]
connect_bd_net [get_bd_pins $logic_one/dout] [get_bd_pins $vtc/clken] [get_bd_pins $vtc/s_axi_aclken] [get_bd_pins $video_out/aclken]
connect_bd_net [get_bd_pins $video_out/vtg_ce] [get_bd_pins $vtc/gen_clken]

# Interrupt aggregation: DMA, VDMA, video timing and three PL event classes.
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_irq]
set_property CONFIG.NUM_PORTS {6} $irq_concat
connect_bd_net [get_bd_pins $dma/s2mm_introut] [get_bd_pins $irq_concat/In0]
connect_bd_net [get_bd_pins $vdma/mm2s_introut] [get_bd_pins $irq_concat/In1]
connect_bd_net [get_bd_pins $vtc/irq] [get_bd_pins $irq_concat/In2]
foreach irq_index {3 4 5} irq_name {pl_snapshot_irq pl_harmonic_irq pl_fault_irq} {
    set irq_port [create_bd_port -dir I $irq_name]
    connect_bd_net $irq_port [get_bd_pins $irq_concat/In${irq_index}]
}
connect_bd_net [get_bd_pins $irq_concat/dout] [get_bd_pins $ps/IRQ_F2P]

# Stable software-visible address map.
assign_bd_address -offset 0x40000000 -range 64K [get_bd_addr_segs $bram_ctrl/S_AXI/Mem0]
assign_bd_address -offset 0x40400000 -range 64K [get_bd_addr_segs $dma/S_AXI_LITE/Reg]
assign_bd_address -offset 0x43000000 -range 64K [get_bd_addr_segs $vdma/S_AXI_LITE/Reg]
assign_bd_address -target_address_space [get_bd_addr_spaces $vdma/Data_MM2S] [get_bd_addr_segs $ps/S_AXI_HP0/HP0_DDR_LOWOCM]
assign_bd_address -target_address_space [get_bd_addr_spaces $dma/Data_S2MM] [get_bd_addr_segs $ps/S_AXI_HP1/HP1_DDR_LOWOCM]
assign_bd_address -target_address_space [get_bd_addr_spaces $dma/Data_SG] [get_bd_addr_segs $ps/S_AXI_HP1/HP1_DDR_LOWOCM]

validate_bd_design
save_bd_design
