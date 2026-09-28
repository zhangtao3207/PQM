# 以官方 37_zynq_lvgl 的 BD 为基线的构建脚本。
#
# 背景：app/main.c 需要 axi_gpio_0(0x41200000，读 LCD ID)、axi_vdma_0(0x43000000)、
#       clk_wiz_0(0x43C00000，运行时配像素时钟)、v_tc_0(0x43C10000)。
#       原先照抄的 PQM_SOC/pqm_ps BD 这四样全无，导致 app 编不过/上板黑屏。
#       官方 37_zynq_lvgl BD 提供全部四样，故以它为基线。
#
# 运行（工作目录必须是 build_official，否则 PS7 会把 NA/ 写进源码根）：
#   cd vivado\build_official
#   vivado.bat -mode batch -source ..\scripts\build_official_base.tcl

set script_dir [file normalize [file dirname [info script]]]
set vivado_dir [file normalize [file join $script_dir ..]]
set build_dir  [file join $vivado_dir build_official]
set bd_src     [file join $vivado_dir src bd_official system]
set rpt_dir    [file join $vivado_dir reports_official]

file mkdir $build_dir
file mkdir $rpt_dir

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

puts "=== 创建工程（part xc7z020clg400-2）==="
create_project -force lcd_base $build_dir -part xc7z020clg400-2

puts "=== 添加自定义 IP 仓库（rgb2lcd）==="
# BD 里的 system_rgb2lcd_0_0 是阿波罗自定义 IP (www.alientek.com:user:rgb2lcd:1.0)。
# 官方 37_zynq_lvgl 工程自身不带 ip_repo，其 xpr 的 IPRepoPath 指向作者本机路径
# (<...>/BaiduNetdiskDownload/ZYNQ_Vitis_7020/35_touch_draw_lcd/ip_repo)，本机不存在。
# 不显式指定仓库，该 IP 的 definition 无法解析，generate_target 会失败。
set ip_repo_dir [file join $vivado_dir ip_repo]
if {[llength [glob -nocomplain -directory $ip_repo_dir *]] > 0} {
    set_property ip_repo_paths [list $ip_repo_dir] [current_project]
    update_ip_catalog -rebuild
    puts "ip_repo_paths: $ip_repo_dir"
} else {
    puts "注意: $ip_repo_dir 为空，system_rgb2lcd_0_0 可能无法解析"
}

puts "=== 复制 BD 到工程目录之外 ==="
# Vivado 要求 sub-design（BD）位于工程目录结构之外，否则报 [filemgmt 20-1381]。
set bd_dst [file join $vivado_dir bd official system]
set bd_parent [file dirname $bd_dst]
file delete -force $bd_parent
file mkdir $bd_parent
copy_tree $bd_src $bd_dst

puts "=== 改写 BD/xci 内嵌的生成路径（关键）==="
# 官方 BD 与各 xci 里的 gen_directory / OUTPUTDIR 是相对原工程的路径。
# 若不改写：BD 报 locked、IP 输出生成不出来(综合报 module not found)、
# 且 Vivado 会把生成物写进只读参考工程并在源码根建 zynq_lvgl.gen/。
# 做法是把这些值统一改写为"本工程内的绝对路径"，而不是清空
# （清空会让 IP 缺输出产物，同样综合失败）。
set gen_ip_dir [file join $bd_dst ip]
set patched 0

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

# system.bd 的 gen_directory 指向 BD 自己所在目录
set bd_file_path [file join $bd_dst system.bd]
set bd_dir_native [string map {\\ /} $bd_dst]
incr patched [patch_file $bd_file_path [list \
    {("gen_directory"\s*:\s*")[^"]*(")} "\\1${bd_dir_native}\\2" ]]

# 每个 IP 的 xci：把自己所在目录写进 gen_directory / OUTPUTDIR
foreach xci [glob -nocomplain -directory $gen_ip_dir -types d *] {
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

puts "=== 加入 BD ==="
add_files -norecurse $bd_file_path
set bd_file [get_files -quiet $bd_file_path]
if {$bd_file eq ""} { error "BD 未加入：$bd_file_path" }
puts "BD: $bd_file"

puts "=== 升级 locked IP（关键）==="
# 官方例程的 IP 定制于 Vivado 2020.2，本机是 2022.2，IP 定义 revision 不同 ⇒
# 全部 locked，generate_target 生成不出输出产物，综合报 module not found。
# 必须显式 upgrade_ip 才能解锁。
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

puts "=== 生成 BD 与 IP 输出产物 ==="
generate_target all $bd_file
foreach ip [get_ips -quiet] { catch { generate_target all $ip } }

set still_locked 0
foreach ip [get_ips -quiet] {
    if {[get_property IS_LOCKED $ip] == 1} { puts "  ⚠ 仍 locked: $ip"; incr still_locked }
}
puts "仍 locked 的 IP 数: $still_locked"
if {$still_locked > 0} {
    report_ip_status -file [file join $build_dir ip_status_locked.rpt]
    error "仍有 $still_locked 个 IP 处于 locked，输出产物不完整，综合必然报 module not found"
}

puts "=== 顶层与约束 ==="
add_files -norecurse [file join $vivado_dir src system_wrapper_official.v]
add_files -fileset constrs_1 -norecurse [file join $vivado_dir constrs official_lcd.xdc]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "=== 综合 ==="
reset_run synth_1 -quiet
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "综合失败，见 $build_dir/lcd_base.runs/synth_1/runme.log"
}
puts "=== 综合完成 ==="

puts "=== 实现 + 比特流 ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "实现失败，见 $build_dir/lcd_base.runs/impl_1/runme.log"
}
puts "=== 实现完成 ==="

puts "=== 报告 ==="
open_run impl_1
report_utilization    -file [file join $rpt_dir post_impl_utilization.rpt]
report_timing_summary -file [file join $rpt_dir post_impl_timing_summary.rpt]
close_design

puts "=== 导出 XSA ==="
set xsa [file join $vivado_dir official_base.xsa]
write_hw_platform -fixed -include_bit -force -file $xsa
puts "XSA: $xsa"
puts "=== done ==="
