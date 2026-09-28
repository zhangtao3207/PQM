# 直接读 app 里喂给相位图的两个点数组，验证「零幅值谐波不画相位柱」是否生效。
# 不用点屏幕：这两个数组就是图上的柱子。
#   PhasePointsPos  0x001ec4c8  16 x int16（LV_USE_LARGE_COORD=0 -> lv_coord_t=int16）
#   PhasePointsNeg  0x001ec4e8  16 x int16
# LV_CHART_POINT_NONE = INT16_MIN = -32768
# 运行：& 'D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat' scripts\check_phase_points.tcl

connect
targets -set -filter {name =~ "APU*"}

proc rdw {addr count} {
    if {[catch {mrd -force $addr $count} out]} { return {} }
    set vals {}
    foreach line [split $out "\n"] {
        set line [string trim $line]
        if {$line eq ""} { continue }
        set c [string first ":" $line]
        if {$c < 0} { continue }
        set v [string trim [string range $line [expr {$c + 1}] end]]
        if {[string range $v 0 1] eq "0x"} { set v [string range $v 2 end] }
        lappend vals $v
    }
    return $vals
}

proc s16 {hexword half} {
    set w [string trim $hexword]
    if {[string length $w] > 8} { set w [string range $w [expr {[string length $w] - 8}] end] }
    set v [expr {"0x$w"}]
    if {$half == 0} { set v [expr {$v & 0xFFFF}] } else { set v [expr {($v >> 16) & 0xFFFF}] }
    if {$v >= 0x8000} { set v [expr {$v - 0x10000}] }
    return $v
}

proc show {name addr} {
    set w [rdw $addr 8]
    if {[llength $w] < 8} { puts "  $name: 读取失败"; return }
    set out {}
    for {set i 0} {$i < 8} {incr i} {
        set lo [s16 [lindex $w $i] 0]
        set hi [s16 [lindex $w $i] 1]
        lappend out "H[expr {$i*2}]=[expr {($lo == -32768) ? {NONE} : $lo}]"
        lappend out "H[expr {$i*2+1}]=[expr {($hi == -32768) ? {NONE} : $hi}]"
    }
    puts "  $name: [join $out {  }]"
}

puts "---- 相位图两个 series 的点数组（LV_CHART_POINT_NONE 显示为 NONE）----"
show "Pos(蓝)" 0x001ec4c8
show "Neg(红)" 0x001ec4e8
puts ""
puts "---- 幅度图对照（16 位 U 占比 / I 占比 交错）----"
set mw [rdw 0x001ec488 16]
puts "  MagnitudePoints[0] (U): [lindex $mw 0..7]"
set u {}
set i2 {}
for {set k 0} {$k < 16} {incr k} {
    set wv [lindex $mw $k]
    set lo [s16 $wv 0]
    set hi [s16 $wv 1]
    if {$k < 8} {
        lappend u "H[expr {$k*2}]=[expr {($lo == -32768) ? {NONE} : $lo}]" "H[expr {$k*2+1}]=[expr {($hi == -32768) ? {NONE} : $hi}]"
    } else {
        lappend i2 "H[expr {($k-8)*2}]=[expr {($lo == -32768) ? {NONE} : $lo}]" "H[expr {($k-8)*2+1}]=[expr {($hi == -32768) ? {NONE} : $hi}]"
    }
}
puts "  U: [join $u {  }]"
puts "  I: [join $i2 {  }]"
puts ""
puts "---- 谐波表原始数据（当前 bank 的 H0..H3）----"
puts "  [rdw 0x40001000 8]"
puts "done"
exit
