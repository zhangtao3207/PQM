# 先验证「经 JTAG 读 app 的 .data/.bss 变量」这条路是不是通的：
# 读若干个初值已知的符号，对不上就说明地址或读法有问题，而不是固件的锅。
# 运行：& 'D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat' scripts\check_app_vars.tcl

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

proc u32 {addr} {
    set w [rdw $addr 1]
    if {[llength $w] < 1} { return ERR }
    set v [string trim [lindex $w 0]]
    if {[string length $v] > 8} { set v [string range $v [expr {[string length $v] - 8}] end] }
    return [expr {"0x$v"}]
}

puts "---- 初值已知的变量（地址来自 arm-none-eabi-nm）----"
puts [format "  PQMUI_UMaxX100          @0x001e6264 = %d   (应 38890)" [u32 0x001e6264]]
puts [format "  PQMUI_IMaxX100          @0x001e6268 = %d   (应 38890)" [u32 0x001e6268]]
puts [format "  frame_buffer_addr       @0x001e5d18 = 0x%08X (应 0x01100000)" [u32 0x001e5d18]]
puts [format "  PQMUI_FrequencyActive   @0x001ec1e4 = %d   (0=时域页)" [u32 0x001ec1e4]]
puts [format "  PQMUI_HarmonicsAvailable@0x001ec1ea = %d   (应 1)" [u32 0x001ec1ea]]
puts [format "  PQMUI_HarmonicWindowStart@0x001ec468 = %d  (应 0)" [u32 0x001ec468]]
puts [format "  PQMUI_ShmStatus         @0x001ed258 = 0x%08X" [u32 0x001ed258]]

puts ""
puts "---- PQMUI_LatestHarmonics（@0x001ec264，结构体）----"
puts "  前 24 字：[rdw 0x001ec264 24]"

puts ""
puts "---- ShmHarmonics（@0x001ed2e0）----"
puts "  前 24 字：[rdw 0x001ed2e0 24]"

puts ""
puts "---- 相位/幅度点数组 ----"
puts "  PhasePointsPos @0x001ec4c8 : [rdw 0x001ec4c8 8]"
puts "  PhasePointsNeg @0x001ec4e8 : [rdw 0x001ec4e8 8]"
puts "  MagnitudePoints@0x001ec488 : [rdw 0x001ec488 16]"
puts "done"
exit
