# PQM PS block-design contract check. Run only after creating FPGA/prj_soc.
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]
set project_file [file join $fpga_dir prj_soc PQM_SOC.xpr]

if {![file exists $project_file]} {
    error "PQM SoC project not found: $project_file"
}

open_project $project_file
set bd_file [get_files -quiet */pqm_ps.bd]
if {[llength $bd_file] != 1} {
    error "Expected exactly one pqm_ps.bd, found [llength $bd_file]"
}
open_bd_design $bd_file

set required_cells {
    processing_system7_0
    axi_interconnect_ctrl
    axi_bram_ctrl_0
    blk_mem_gen_shared
    axi_dma_0
    axis_sample_slice
    axis_sample_cdc
    axi_vdma_0
    v_tc_0
    v_axi4s_vid_out_0
    clk_wiz_pixel
    rst_fclk0
    rst_pixel
    xlconcat_irq
}

foreach cell $required_cells {
    if {[llength [get_bd_cells -quiet $cell]] == 0} {
        error "Missing required BD cell: $cell"
    }
}

set ps [get_bd_cells processing_system7_0]
if {[get_property CONFIG.PCW_UIPARAM_DDR_PARTNO $ps] ne {MT41K256M16 RE-125}} {
    error "Incorrect DDR compatibility part"
}
if {[get_property CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH $ps] ne {32 Bit}} {
    error "Incorrect DDR bus width"
}

set interface_contract [dict create \
    S_AXIS_SAMPLES 8 \
    M_AXIS_VIDEO_RGB565 2 \
    S_AXIS_VIDEO_RGB888 3]
dict for {interface_name expected_bytes} $interface_contract {
    set interface [get_bd_intf_ports -quiet $interface_name]
    if {[llength $interface] != 1} {
        error "Missing external interface: $interface_name"
    }
    set actual_bytes [get_property CONFIG.TDATA_NUM_BYTES $interface]
    if {$actual_bytes != $expected_bytes} {
        error "Incorrect width for $interface_name: expected $expected_bytes bytes, got $actual_bytes"
    }
}

set expected_addresses [dict create \
    SEG_axi_bram_ctrl_0_Mem0 0x40000000 \
    SEG_axi_dma_0_Reg 0x40400000 \
    SEG_axi_vdma_0_Reg 0x43000000]

dict for {segment_name expected_offset} $expected_addresses {
    set segment [get_bd_addr_segs -quiet processing_system7_0/Data/$segment_name]
    if {[llength $segment] != 1} {
        error "Missing address segment: $segment_name"
    }
    set actual_offset [get_property OFFSET $segment]
    if {[expr {$actual_offset}] != [expr {$expected_offset}]} {
        error "Incorrect address for $segment_name: expected $expected_offset, got $actual_offset"
    }
}

validate_bd_design
puts "PQM PS block-design contract passed"
close_project
