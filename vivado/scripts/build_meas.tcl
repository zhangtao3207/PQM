# ============================================================================
# PQM2 测量版构建脚本：官方基线 BD + PS/PL 共享内存 + PL 测量链。
#
# 与 build_official_base.tcl 的关系：
#   前 3/4 段（建工程、ip_repo、把 BD 复制到工程目录之外、改写内嵌生成路径、
#   upgrade_ip）与它逐字同源，官方基线那套流程保持不变，可随时回退。
#   差别只有：BD 存到 vivado/bd/meas/system（不覆盖 official 那份）、
#   多一步“在打开的 BD 上增补共享内存”、顶层换成 pqm2_meas_top。
#
# 运行（工作目录必须是 build_meas，否则 PS7 会把 NA/ 写进源码根）：
#   $env:MEAS_STAGE="bd"      ; 只做 BD，快速失败
#   $env:MEAS_STAGE="synth"   ; 做到综合
#   $env:MEAS_STAGE="all"     ; 综合+实现+比特流+XSA+报告
#   $env:MEAS_SHM_MODE="extend"|"insert"   ; 共享内存挂 AXI 的方式
#   $env:MEAS_FRESH="1"       ; 删掉 build_meas 重建
# ============================================================================

set stage "all"
if {[info exists ::env(MEAS_STAGE)]}  { set stage    $::env(MEAS_STAGE) }
set shm_mode "extend"
if {[info exists ::env(MEAS_SHM_MODE)]} { set shm_mode $::env(MEAS_SHM_MODE) }
set fresh 0
if {[info exists ::env(MEAS_FRESH)]}  { set fresh 1 }

set script_dir [file normalize [file dirname [info script]]]
set vivado_dir [file normalize [file join $script_dir ..]]
set repo_dir   [file normalize [file join $vivado_dir ..]]
set build_dir  [file join $vivado_dir build_meas]
set bd_src     [file join $vivado_dir src bd_official system]
set bd_dst     [file join $vivado_dir bd meas system]
set rpt_dir    [file join $vivado_dir reports_meas]
set proj_name  meas
set xpr        [file join $build_dir "${proj_name}.xpr"]
set xsa        [file join $vivado_dir pqm2_meas.xsa]
set bit_out    [file join $vivado_dir pqm2_meas.bit]

puts "=== PQM2 测量版构建：stage=$stage shm_mode=$shm_mode fresh=$fresh ==="

proc copy_tree {src dst} {
    file mkdir $dst
    foreach entry [glob -nocomplain -directory $src *] {
        set target [file join $dst [file tail $entry]]
        if {[file isdirectory $entry]} {
            copy_tree $entry $target
        } else {
            file copy -force $entry $target
        }
    }
}

proc patch_file {f replacements} {
    set fh [open $f r]
    fconfigure $fh -translation binary
    set txt [read $fh]
    close $fh
    set new $txt
    foreach {pat repl} $replacements {
        regsub -all $pat $new $repl new
    }
    if {$new ne $txt} {
        set fh [open $f w]
        fconfigure $fh -translation binary
        puts -nonewline $fh $new
        close $fh
        return 1
    }
    return 0
}

# ---------------------------------------------------------------------------
# A. 工程：存在就打开（迭代快），MEAS_FRESH=1 才从头建
# ---------------------------------------------------------------------------
set created 0
if {$fresh && [file exists $build_dir]} {
    puts "=== MEAS_FRESH=1：删除 $build_dir ==="
    file delete -force $build_dir
}

if {[file exists $xpr]} {
    puts "=== 打开已有工程 $xpr ==="
    open_project $xpr
} else {
    file mkdir $build_dir
    file mkdir $rpt_dir
    puts "=== 创建工程（part xc7z020clg400-2）==="
    create_project -force $proj_name $build_dir -part xc7z020clg400-2
    set created 1

    puts "=== 添加自定义 IP 仓库（rgb2lcd）==="
    set ip_repo_dir [file join $vivado_dir ip_repo]
    if {[llength [glob -nocomplain -directory $ip_repo_dir *]] > 0} {
        set_property ip_repo_paths [list $ip_repo_dir] [current_project]
        update_ip_catalog -rebuild
        puts "ip_repo_paths: $ip_repo_dir"
    } else {
        error "ip_repo 为空，system_rgb2lcd_0_0 无法解析：$ip_repo_dir"
    }

    puts "=== 复制 BD 到工程目录之外 ==="
    set bd_parent [file dirname $bd_dst]
    file delete -force $bd_parent
    file mkdir $bd_parent
    copy_tree $bd_src $bd_dst

    puts "=== 改写 BD/xci 内嵌的生成路径 ==="
    set bd_file_path [file join $bd_dst system.bd]
    set bd_dir_native [string map {\\ /} $bd_dst]
    set patched 0
    incr patched [patch_file $bd_file_path [list \
        {("gen_directory"\s*:\s*")[^"]*(")} "\\1${bd_dir_native}\\2" ]]
    foreach xci [glob -nocomplain -directory [file join $bd_dst ip] -types d *] {
        set xci_name [file tail $xci]
        set f [file join $xci "${xci_name}.xci"]
        if {![file exists $f]} { continue }
        set native [string map {\\ /} $xci]
        incr patched [patch_file $f [list \
            {("gen_directory"\s*:\s*")[^"]*(")}    "\\1${native}\\2" \
            {("OUTPUTDIR"\s*:\s*\[\s*\{\s*"value"\s*:\s*")[^"]*(")} "\\1${native}\\2" \
            {(RUNTIME_PARAM\.OUTPUTDIR">)[^<]*(<)} "\\1${native}\\2" ]]
    }
    puts "已改写生成路径的文件数: $patched"

    puts "=== 加入 BD 与自带 IP ==="
    add_files -norecurse [file join $bd_dst system.bd]
    add_files -norecurse [file join $vivado_dir ip clk_wiz_0 clk_wiz_0.xci]
    add_files -norecurse [file join $vivado_dir ip rom_atan_lut_1024 rom_atan_lut_1024.xci]
}

set bd_file [get_files -quiet [file join $bd_dst system.bd]]
if {$bd_file eq ""} { error "BD 未加入：$bd_dst\\system.bd" }
puts "BD: $bd_file"

# ---------------------------------------------------------------------------
# B. 升级 locked IP（2020.2/2021.x 定制的 IP 在 2022.2 下 locked，必须先升级）
# ---------------------------------------------------------------------------
puts "=== 升级 locked IP ==="
set all_ips [get_ips -quiet]
if {[llength $all_ips] > 0} {
    puts "IP 数: [llength $all_ips]"
    if {[catch {upgrade_ip $all_ips} err]} {
        puts "批量 upgrade_ip 失败（$err），改为逐个升级"
        foreach ip $all_ips {
            if {[catch {upgrade_ip $ip} e2]} { puts "  $ip -> $e2" }
        }
    }
    puts "upgrade_ip 完成"
}

# ---------------------------------------------------------------------------
# C. BD 增补共享内存 + 校验
# ---------------------------------------------------------------------------
puts "=== 打开 BD 增补共享内存 ==="
open_bd_design $bd_file
source [file join $script_dir bd_add_shared_mem.tcl]
if {[catch {bd_add_shared_memory $shm_mode} e]} {
    puts "BD-SHM 增补失败: $e"
    catch {close_bd_design [current_bd_design]}
    error "BD 增补失败，见上面第一条错误"
}
puts "=== validate_bd_design ==="
if {[catch {validate_bd_design} e]} {
    catch {close_bd_design [current_bd_design]}
    error "validate_bd_design 失败: $e"
}
puts "=== BD 校验通过，保存 ==="
save_bd_design
# 注意：2022.2 的 close_bd_design 必须显式给名字，不能省略参数。
close_bd_design [current_bd_design]

# ---------------------------------------------------------------------------
# D. 生成 BD 与 IP 输出产物
# ---------------------------------------------------------------------------
puts "=== 生成 BD 与 IP 输出产物 ==="
generate_target all $bd_file
foreach ip [get_ips -quiet] { catch { generate_target all $ip } }

set still_locked 0
foreach ip [get_ips -quiet] {
    if {[get_property IS_LOCKED $ip] == 1} { puts "  ! 仍 locked: $ip"; incr still_locked }
}
puts "仍 locked 的 IP 数: $still_locked"
if {$still_locked > 0} {
    report_ip_status -file [file join $build_dir ip_status_locked.rpt]
    error "仍有 $still_locked 个 IP 处于 locked，综合必然报 module not found"
}

# ---------------------------------------------------------------------------
# E. 顶层、RTL、约束
# ---------------------------------------------------------------------------
puts "=== 加入 PL 测量链 RTL ==="
set rtl_dir [file join $repo_dir pl rtl]
set rtl_files [list]
foreach f [glob -nocomplain -directory $rtl_dir -types f *.v *.sv] { lappend rtl_files $f }
foreach d [glob -nocomplain -directory $rtl_dir -types d *] {
    foreach f [glob -nocomplain -directory $d -types f *.v *.sv] { lappend rtl_files $f }
    foreach d2 [glob -nocomplain -directory $d -types d *] {
        foreach f [glob -nocomplain -directory $d2 -types f *.v *.sv] { lappend rtl_files $f }
        foreach d3 [glob -nocomplain -directory $d2 -types d *] {
            foreach f [glob -nocomplain -directory $d3 -types f *.v *.sv] { lappend rtl_files $f }
            foreach d4 [glob -nocomplain -directory $d3 -types d *] {
                foreach f [glob -nocomplain -directory $d4 -types f *.v *.sv] { lappend rtl_files $f }
            }
        }
    }
}
puts "RTL 文件数: [llength $rtl_files]"
add_files -norecurse $rtl_files
# SV 头文件与 vh 的头文件搜索路径
set_property include_dirs [list [file join $rtl_dir PSInterface]] [current_fileset]
# 系统顶层
add_files -norecurse [file join $vivado_dir src pqm2_meas_top.v]
add_files -fileset constrs_1 -norecurse [file join $vivado_dir constrs meas_pins.xdc]
set_property top pqm2_meas_top [current_fileset]
update_compile_order -fileset sources_1
puts "顶层: [get_property top [current_fileset]]"

if {$stage eq "bd"} {
    puts "=== STAGE=bd：到此为止（BD 校验 + 生成产物 + 顶层设置均已通过）==="
    puts "=== done ==="
    return
}

# ---------------------------------------------------------------------------
# F. 综合
# ---------------------------------------------------------------------------
puts "=== 综合 ==="
# MEAS_SKIP_SYNTH=1 时，若综合已完成就直接复用（迭代时省一次 6 分钟）。
# 可复现构建走 MEAS_FRESH=1 + stage=all，那条路会从头综合。
set skip_synth 0
if {[info exists ::env(MEAS_SKIP_SYNTH)]} { set skip_synth 1 }
set synth_progress [get_property PROGRESS [get_runs synth_1]]
if {$skip_synth && $synth_progress eq "100%"} {
    puts "=== 复用已有综合结果（PROGRESS=100%，MEAS_SKIP_SYNTH=1）==="
} else {
    reset_run synth_1 -quiet
    launch_runs synth_1 -jobs 8
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        set log [file join $build_dir ${proj_name}.runs synth_1 runme.log]
        puts "综合失败，runme.log 里的 ERROR："
        if {[file exists $log]} {
            set fh [open $log r]
            foreach line [split [read $fh] "\n"] {
                if {[string match "*ERROR:*" $line]} { puts "  $line" }
            }
            close $fh
        }
        error "综合失败，见 $log"
    }
}
puts "=== 综合完成 ==="

if {$stage eq "synth"} {
    puts "=== STAGE=synth：到此为止 ==="
    puts "=== done ==="
    return
}

# ---------------------------------------------------------------------------
# G. 实现 + 比特流
# ---------------------------------------------------------------------------
puts "=== 实现 + 比特流 ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    set log [file join $build_dir ${proj_name}.runs impl_1 runme.log]
    puts "实现失败，runme.log 里的 ERROR："
    if {[file exists $log]} {
        set fh [open $log r]
        foreach line [split [read $fh] "\n"] {
            if {[string match "*ERROR:*" $line]} { puts "  $line" }
        }
        close $fh
    }
    error "实现失败，见 $log"
}
puts "=== 实现完成 ==="

puts "=== 报告 ==="
open_run impl_1
report_utilization     -file [file join $rpt_dir post_impl_utilization.rpt]
report_timing_summary  -file [file join $rpt_dir post_impl_timing_summary.rpt]
report_drc             -file [file join $rpt_dir post_impl_drc.rpt]
close_design

# 把 bit 复制到仓库根附近的固定位置，方便烧录脚本引用
set impl_bit [file join $build_dir ${proj_name}.runs impl_1 pqm2_meas_top.bit]
if {[file exists $impl_bit]} {
    file copy -force $impl_bit $bit_out
    puts "BIT: $bit_out ([file size $bit_out] B)"
} else {
    puts "警告：未找到 $impl_bit"
}

puts "=== 导出 XSA ==="
write_hw_platform -fixed -include_bit -force -file $xsa
puts "XSA: $xsa ([file size $xsa] B)"
puts "=== done ==="
