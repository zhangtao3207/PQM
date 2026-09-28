# ============================================================================
# 板上频率稳定性验收：连采 10 次「频率」标量读数（间隔 2 秒），报出 10 个值与极差。
#
# 运行（先跑过 scripts/flash_meas.tcl，板子上 app 已在跑）：
#   D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat C:\Users\zhangtao\Desktop\PQM2\scripts\read_freq_10x.tcl
#
# 注意：
#  - 读 PL 从设备必须把 target 切到 APU，否则 DAP 报
#    "Blocked address 0x40000000. PL AXI slave ports access is not allowed."
#  - 本脚本**不做任何复位**：rst -system 会把正在跑的 app 打掉。
#    APU target 不可见时只报错，交给 flash_meas.tcl 重新初始化。
#  - 全程不 stop CPU，CPU 保持 Running，读到的就是运行时数据。
#
# ABI（pl/rtl/PSInterface/pqm_shared_memory_map.vh）：标量快照 word 0x10..0x1D 为工程量 x100。
# ============================================================================
set repo_dir {C:/Users/zhangtao/Desktop/PQM2}
set out_file [file join $repo_dir export board_freq_10x.log]
set ::fh [open $out_file w]
fconfigure $::fh -encoding utf-8 -translation lf

set base 0x40000000
set w_urms   0x10
set w_irms   0x11
set w_phase  0x15
set w_thdu   0x1A
set w_freq   0x14
set w_valid  0x1F

proc plog {m} { puts $m; catch { puts $::fh $m; flush $::fh } }

proc rd {a} {
    if {[catch {mrd -force $a} v]} { return "" }
    set t [string trim [lindex [split $v ":"] end]]
    if {![regexp {^[0-9A-Fa-f]+$} $t]} { return "" }
    return [expr "0x$t"]
}

proc sx {v} {
    if {$v >= 2147483648} { return [expr {$v - 4294967296}] }
    return $v
}

# 与 scripts/report_shm.ps1 的 Fmt-X100 同口径：整数部分向下取整，不做四舍五入
proc f2 {v} {
    set neg [expr {$v < 0}]
    set a   [expr {abs($v)}]
    set w   [expr {$a / 100}]
    set f   [expr {$a % 100}]
    return [format "%s%d.%02d" [expr {$neg ? "-" : ""}] $w $f]
}

connect

if {[catch {targets -set -filter {name =~ "APU*"}} e]} {
    plog "ERROR: APU target 不可见（$e）。本脚本不复位，请先跑 scripts/flash_meas.tcl。"
    close $::fh
    return
}
plog "target: APU（CPU 保持 Running）"

set magic [rd $base]
plog [format "magic 0x40000000 = 0x%08X （应为 0x50514D31）" $magic]

plog ""
plog "==== 连续 10 次频率读数（间隔 2 秒）===="
plog "  #   raw(x100)   Frequency      valid"
set fmin ""
set fmax ""
set samples {}
for {set i 1} {$i <= 10} {incr i} {
    set fr ""
    while {$fr eq ""} {
        set fr [rd [expr {$base + $w_freq * 4}]]
        if {$fr eq ""} { plog "  第 $i 次读取失败，200 ms 后重试"; after 200 }
    }
    set fr [sx $fr]
    set valid [rd [expr {$base + $w_valid * 4}]]
    set vok [expr {(($valid & 0x020) != 0) ? "OK" : "--"}]
    plog [format "  %2d  %10d   %8s Hz   %s" $i $fr [f2 $fr] $vok]
    lappend samples $fr
    if {$fmin eq "" || $fr < $fmin} { set fmin $fr }
    if {$fmax eq "" || $fr > $fmax} { set fmax $fr }
    if {$i < 10} { after 2000 }
}

set range [expr {$fmax - $fmin}]
plog ""
plog "---- 极差 ----"
plog "  10 次读数（x100）: $samples"
plog "  min = $fmin ([f2 $fmin] Hz)"
plog "  max = $fmax ([f2 $fmax] Hz)"
plog "  极差 = $range (x100) = [f2 $range] Hz"

plog ""
plog "---- 同一时刻的其它字段（确认未被本次改动影响）----"
foreach {name w} [list "U RMS  V" $w_urms "I RMS  A" $w_irms "Phase deg" $w_phase "THD-U  %" $w_thdu] {
    set v [sx [rd [expr {$base + $w * 4}]]]
    plog "  $name = [f2 $v]   (raw $v)"
}
plog [format "  validity word0x1F = 0x%08X" [rd [expr {$base + $w_valid * 4}]]]

plog "=== done ==="
close $::fh
