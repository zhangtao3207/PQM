# ============================================================================
# PQM2 Vivado 2022.2 构建脚本
#
#   用法（工程根目录 C:\Users\zhangtao\Desktop\PQM2）：
#     vivado -mode batch -source vivado/scripts/build.tcl \
#            -log vivado/build/vivado_build.log -journal vivado/build/vivado_build.jou
#
#   做什么：
#     1) create_project 到 vivado/build/，part = xc7z020clg400-2
#     2) 加入 BD（vivado/src/bd/pqm_ps/pqm_ps.bd，含其 ip/ 子目录）
#     3) 加入 IP：clk_wiz_0、rom_atan_lut_1024
#     4) 加入 pl/rtl 下全部 RTL（.v/.sv；.vh 只作 include，设 verilog_include_dirs）
#     5) 加入 vivado/src/pqm2_top.v 并设为 top
#     6) 加入 vivado/constrs/pqm2_pins.xdc
#     7) generate_target -> synth_1 -> impl_1 -to_step write_bitstream
#     8) 报告写到 vivado/reports/，XSA 写到 vivado/，比特流复制到 vivado/system.bit
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
set viv_dir    [file normalize [file join $script_dir ..]]
set root_dir   [file normalize [file join $viv_dir ..]]
set build_dir  [file join $viv_dir build]
set report_dir [file join $viv_dir reports]

set proj_name  pqm2_soc
set part_name  xc7z020clg400-2
set xsa_path   [file join $viv_dir pqm2_system.xsa]
set bit_copy   [file join $viv_dir system.bit]

file mkdir $build_dir
file mkdir $report_dir

puts "PQM2_ROOT      = $root_dir"
puts "PQM2_VIV_DIR   = $viv_dir"
puts "PQM2_BUILD_DIR = $build_dir"

# ---------------------------------------------------------------------------
# 工具过程
# ---------------------------------------------------------------------------
proc find_files_rec {dir patterns} {
    set result [list]
    foreach p $patterns {
        foreach f [glob -nocomplain -directory $dir -types f $p] {
            lappend result $f
        }
    }
    foreach sub [glob -nocomplain -directory $dir -types d *] {
        foreach f [find_files_rec $sub $patterns] { lappend result $f }
    }
    return $result
}

proc read_text {path} {
    set fh [open $path r]
    set data [read $fh]
    close $fh
    return $data
}

proc write_text {path data} {
    set fh [open $path w]
    puts -nonewline $fh $data
    close $fh
}

# 计算 target 相对 base 的相对路径（用 / 分隔，Vivado/Tcl 都能吃）
proc relpath {target base} {
    set t [file split [file normalize $target]]
    set b [file split [file normalize $base]]
    set i 0
    while {$i < [llength $b] && $i < [llength $t] && [string equal [lindex $b $i] [lindex $t $i]]} {
        incr i
    }
    set out [list]
    for {set j $i} {$j < [llength $b]} {incr j} { lappend out ".." }
    foreach x [lrange $t $i end] { lappend out $x }
    return [join $out "/"]
}

proc dump_tail {path n} {
    if {![file exists $path]} { puts "  (no such file: $path)"; return }
    set fh [open $path r]
    set data [read $fh]
    close $fh
    set lines [split $data "\n"]
    set total [llength $lines]
    set start [expr {$total > $n ? $total - $n : 0}]
    puts "---- tail($n) of $path ----"
    foreach l [lrange $lines $start end] { puts $l }
    puts "---- end tail ----"
}

proc wait_run {run} {
    wait_on_run $run
    set st [get_property STATUS [get_runs $run]]
    set pr [get_property PROGRESS [get_runs $run]]
    puts "== RUN $run : STATUS = $st / PROGRESS = $pr"
    flush stdout
    if {$pr ne "100%"} {
        set rd [get_property DIRECTORY [get_runs $run]]
        dump_tail [file join $rd runme.log] 80
        error "PQM2_BUILD_ERROR: run $run did not complete (STATUS=$st PROGRESS=$pr)"
    }
}

# ---------------------------------------------------------------------------
# 1) 建工程
# ---------------------------------------------------------------------------
# 0) 清掉上一轮可能残留在源码根的 BD 生成目录
# ---------------------------------------------------------------------------
foreach stray [list [file join $root_dir PQM_SOC.gen] [file join $root_dir NA]] {
    if {[file exists $stray]} {
        puts "== removing stray dir: $stray"
        file delete -force $stray
    }
}

# ---------------------------------------------------------------------------
if {[file exists [file join $build_dir ${proj_name}.xpr]]} {
    puts "== removing previous project =="
    close_project -quiet
    file delete -force [file join $build_dir $proj_name]
    file delete -force [file join $build_dir ${proj_name}.xpr]
    file delete -force [file join $build_dir ${proj_name}.xpr.bak]
    foreach ext {cache gen runs srcs sim hw ip_user_files} {
        file delete -force [file join $build_dir ${proj_name}.${ext}]
    }
}

create_project $proj_name $build_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ---------------------------------------------------------------------------
# 2) BD
# ---------------------------------------------------------------------------
set bd_file [file normalize [file join $viv_dir src bd pqm_ps pqm_ps.bd]]
if {![file exists $bd_file]} { error "PQM2_BUILD_ERROR: BD not found: $bd_file" }

# BD 文件以及它 ip/ 子目录下每个嵌套 IP 的 .xci 里都内嵌了原工程的生成目录
# （"gen_directory"/"OUTPUTDIR": "../../../../../../PQM_SOC.gen/..."）。直接复制过来后，
# Vivado 会在源码根下建出 PQM_SOC.gen/ 等目录。这里统一改写成指向本工程自己的 .gen，
# 保证生成物全部落在 vivado/build/ 下。
set bd_dir  [file dirname $bd_file]
set gen_abs [file join $build_dir ${proj_name}.gen sources_1 bd pqm_ps]
set gen_rel [relpath $gen_abs $bd_dir]

set bd_text [read_text $bd_file]
regsub {"gen_directory"\s*:\s*"[^"]*"} $bd_text "\"gen_directory\": \"$gen_rel\"" bd_text
write_text $bd_file $bd_text
puts "== BD gen_directory patched -> $gen_rel"

set ip_patched 0
foreach ip_sub [glob -nocomplain -directory [file join $bd_dir ip] -types d *] {
    set ip_name [file tail $ip_sub]
    set ip_xci  [file join $ip_sub ${ip_name}.xci]
    if {![file exists $ip_xci]} { continue }
    set ip_rel [relpath [file join $gen_abs ip $ip_name] $ip_sub]
    set txt [read_text $ip_xci]
    regsub -all {"gen_directory"\s*:\s*"\.\./[^"]*"} $txt "\"gen_directory\": \"$ip_rel\"" txt
    regsub -all {("OUTPUTDIR"\s*:\s*\[\s*\{\s*"value"\s*:\s*)"[^"]*"} $txt "\\1\"$ip_rel\"" txt
    write_text $ip_xci $txt
    incr ip_patched
}
puts "== nested BD IP xci patched: $ip_patched"

add_files -norecurse -fileset sources_1 [list $bd_file]
puts "== added BD: $bd_file"

# ---------------------------------------------------------------------------
# 3) IP
# ---------------------------------------------------------------------------
set ip_files [list \
    [file normalize [file join $viv_dir ip clk_wiz_0 clk_wiz_0.xci]] \
    [file normalize [file join $viv_dir ip rom_atan_lut_1024 rom_atan_lut_1024.xci]] ]
foreach f $ip_files {
    if {![file exists $f]} { error "PQM2_BUILD_ERROR: IP not found: $f" }
}
add_files -norecurse -fileset sources_1 $ip_files
puts "== added IP: $ip_files"

# ---------------------------------------------------------------------------
# 4) pl/rtl 全部 RTL
# ---------------------------------------------------------------------------
set rtl_dir [file join $root_dir pl rtl]
set rtl_files [find_files_rec $rtl_dir [list *.v *.sv]]
if {[llength $rtl_files] == 0} { error "PQM2_BUILD_ERROR: no RTL found under $rtl_dir" }
add_files -norecurse -fileset sources_1 $rtl_files
puts "== added [llength $rtl_files] RTL files from $rtl_dir"

# .vh 只作 include 文件（`include "pqm_shared_memory_map.vh"），不进设计源
set inc_dirs [list [file join $rtl_dir PSInterface]]
set_property include_dirs $inc_dirs [current_fileset]
puts "== verilog include_dirs = $inc_dirs"

# ---------------------------------------------------------------------------
# 5) PQM2 顶层 + 从参考工程复制来的视频/触摸段 RTL
# ---------------------------------------------------------------------------
set own_srcs [list \
    [file normalize [file join $viv_dir src pqm2_top.v]] \
    [file normalize [file join $viv_dir src touch pqm_touch_iobuf.v]] \
    [file normalize [file join $viv_dir src video pqm_axis_rgb565_to_rgb888.v]] ]
foreach f $own_srcs {
    if {![file exists $f]} { error "PQM2_BUILD_ERROR: source not found: $f" }
}
add_files -norecurse -fileset sources_1 $own_srcs
set_property top pqm2_top [current_fileset]
update_compile_order -fileset sources_1
puts "== top = [get_property top [current_fileset]]"

# ---------------------------------------------------------------------------
# 6) 约束
# ---------------------------------------------------------------------------
set xdc_file [file normalize [file join $viv_dir constrs pqm2_pins.xdc]]
if {![file exists $xdc_file]} { error "PQM2_BUILD_ERROR: XDC not found: $xdc_file" }
add_files -norecurse -fileset constrs_1 [list $xdc_file]
puts "== added XDC: $xdc_file"

# ---------------------------------------------------------------------------
# 7) 生成 BD / IP target
# ---------------------------------------------------------------------------
puts "== generate_target BD =="
generate_target all [get_files -quiet *.bd]
puts "== generate_target IP =="
# 只生成两个独立 IP 的 target。注意不能用 [get_files *.xci]：BD 的嵌套 IP
# 也在工程文件列表里，对它们调 generate_target 会报
# "Nested sub-design can only be generated by its parent sub-design"。
set ip_objs [list]
foreach f $ip_files {
    set o [get_files -quiet $f]
    if {[llength $o] != 1} { error "PQM2_BUILD_ERROR: cannot resolve IP object for $f" }
    lappend ip_objs [lindex $o 0]
}
generate_target all $ip_objs
puts "== BD/IP targets generated =="
flush stdout

# ---------------------------------------------------------------------------
# 8) 综合
# ---------------------------------------------------------------------------
puts "== launch synth_1 =="
flush stdout
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_run synth_1

open_run synth_1 -name synth_1
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
close_design

# ---------------------------------------------------------------------------
# 9) 实现 + 比特流
# ---------------------------------------------------------------------------
puts "== launch impl_1 -to_step write_bitstream =="
flush stdout
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_run impl_1

open_run impl_1

# ---- 报告 ----
report_utilization    -file [file join $report_dir post_impl_utilization.rpt]
report_utilization    -hierarchical -file [file join $report_dir post_impl_utilization_hier.rpt]
report_timing_summary -max_paths 10 -report_unconstrained \
                      -file [file join $report_dir post_impl_timing_summary.rpt]
report_clock_interaction -delay_type max -file [file join $report_dir post_impl_clock_interaction.rpt]
report_clock_utilization -file [file join $report_dir post_impl_clock_utilization.rpt]
report_cdc -details -file [file join $report_dir post_impl_cdc.rpt]
report_drc -file [file join $report_dir post_impl_drc.rpt]
report_methodology -file [file join $report_dir post_impl_methodology.rpt]
report_power -file [file join $report_dir post_impl_power.rpt]

# ---- 保留网络的证据：观察点是否被综合掉 ----
puts "== KEEP CHECK =="
foreach pattern {*pl_adc_tick_pending* *pl_low_range_active* *pl_snapshot_words*} {
    set hits [get_nets -hier -quiet -filter "NAME =~ $pattern"]
    puts "KEEP $pattern -> [llength $hits] net(s)"
    foreach n [lrange $hits 0 2] { puts "    $n" }
}
puts "== KEEP CHECK END =="

# ---- 关键数字直接打到日志，便于核对 ----
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
puts "PQM2_RESULT WNS = $wns"
puts "PQM2_RESULT WHS = $whs"
flush stdout

# ---------------------------------------------------------------------------
# 10) 比特流 + XSA
# ---------------------------------------------------------------------------
set bit_src [get_property DIRECTORY [get_runs impl_1]]
set bit_src [file join $bit_src pqm2_top.bit]
if {[file exists $bit_src]} {
    file copy -force $bit_src $bit_copy
    puts "== bitstream copied to $bit_copy"
} else {
    puts "== WARNING: bitstream not found at $bit_src"
}

puts "== write_hw_platform =="
write_hw_platform -fixed -include_bit -force $xsa_path
puts "== XSA written to $xsa_path"

puts "PQM2_BUILD_DONE"
flush stdout
