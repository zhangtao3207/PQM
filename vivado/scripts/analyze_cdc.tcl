# ============================================================================
# PQM2 时钟域关系取证脚本（只读，不修改工程）
#   用途：为"测量链 50 MHz 晶振域 <-> PS FCLK0 100 MHz AXI 域"的关系给出
#         报告层面的直接证据。
#   用法：vivado -mode batch -source vivado/scripts/analyze_cdc.tcl
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
set viv_dir    [file normalize [file join $script_dir ..]]
set report_dir [file join $viv_dir reports]
file mkdir $report_dir

open_project [file join $viv_dir build pqm2_soc.xpr]
open_run impl_1

# ---- 1) 两个方向的跨时钟路径明细 ----
report_timing -from [get_clocks clk_out1_clk_wiz_0] -to [get_clocks clk_fpga_0] \
    -max_paths 20 -nworst 5 -file [file join $report_dir cross_plclk_to_axiclk.rpt]
report_timing -from [get_clocks clk_fpga_0] -to [get_clocks clk_out1_clk_wiz_0] \
    -max_paths 20 -nworst 5 -file [file join $report_dir cross_axiclk_to_plclk.rpt]

# ---- 2) 共享 BRAM 两个端口各自属于哪个时钟域 ----
puts "=== PQM2_CDC: BD 端口的时钟归属 ==="
foreach pin {u_pqm_ps/PL_SHARED_BRAM_clk u_pqm_ps/PL_AXI_CLK u_pqm_ps/SAMPLE_AXIS_CLK u_pqm_ps/PIXEL_CLK} {
    set p [get_pins -quiet $pin]
    if {[llength $p] == 0} { puts "PQM2_CDC PORT $pin : <not found>"; continue }
    set clks [get_clocks -quiet -of_objects $p]
    set names [list]
    foreach c $clks { lappend names [get_property NAME $c] }
    puts "PQM2_CDC PORT $pin : [join $names {,}]"
}

puts "=== PQM2_CDC: blk_mem_gen_shared 内部 BRAM 原语的时钟引脚 ==="
set found 0
foreach c [get_cells -hier -quiet -filter {REF_NAME =~ RAMB*}] {
    if {![string match *blk_mem_gen_shared* $c]} { continue }
    foreach p [get_pins -quiet -of_objects $c] {
        set rp [get_property REF_PIN_NAME $p]
        if {$rp ni {CLKA CLKB CLKARDCLK CLKBWRCLK}} { continue }
        set clks [get_clocks -quiet -of_objects $p]
        set names [list]
        foreach ck $clks { lappend names [get_property NAME $ck] }
        puts "PQM2_CDC BRAMPIN [get_property NAME $p] : [join $names {,}]"
        incr found
    }
}
puts "PQM2_CDC BRAMPIN total = $found"
puts "PQM2_CDC BRAMPIN total = $found"

# ---- 3) BRAM 端口上究竟有没有被 STA 认领的跨域路径 ----
puts "=== PQM2_CDC: 经过共享 BRAM 的时序路径条数 ==="
foreach pname {ADDRB DINB ENB WEB} {
    set cnt 0
    foreach p [get_pins -hier -quiet -filter "REF_PIN_NAME == $pname"] {
        if {[string match *blk_mem_gen_shared* $p]} { incr cnt }
    }
    puts "PQM2_CDC PORTB $pname pins = $cnt"
}

close_project
puts "PQM2_CDC_ANALYSIS_DONE"
flush stdout
