# 只读诊断：把触摸相关的全局量从运行中的板子上读出来。
#
# 运行：& xsct.bat scripts\diag_touch.tcl
#
# 读的是 ELF 里这些符号的地址（改动代码后地址会变，用 arm-none-eabi-nm -S 重新取）：
#   lcd_id @ 0x00468304
#   tp_dev @ 0x001e5098   init/scan/x[10]/y[10]/sta/touchtype

connect
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
if {[catch {stop} e]} { puts "stop: $e" }

proc rdw {addr} {
    if {[catch {mrd -force $addr} v]} { return -1 }
    set text [string trim [lindex [split $v ":"] end]]
    if {[regexp {^[0-9A-Fa-f]+$} $text]} { return [expr {0x$text}] }
    return -1
}

set lcd_id   [rdw 0x00468304]
set tp_init  [rdw 0x001e5098]
set tp_scan  [rdw 0x001e509c]
set tp_x     [rdw 0x001e50a0]
set tp_y     [rdw 0x001e50b4]
set tp_tail  [rdw 0x001e50c8]

puts "lcd_id                         = 0x[format %08X $lcd_id]"
puts ""
puts "tp_dev.init                    = 0x[format %08X $tp_init]"
puts "tp_dev.scan                    = 0x[format %08X $tp_scan]"
puts "  TP_Scan    = 0x0010741C   （默认值，说明 TP_Init 没选中任何控制器）"
puts "  FT5206_Scan= 0x001056B8"
puts "  GT9147_Scan= 0x0010626C"
puts ""
puts "tp_dev.x[0]                    = [expr {$tp_x & 0xFFFF}]"
puts "tp_dev.y[0]                    = [expr {$tp_y & 0xFFFF}]"
puts "tp_dev.sta                     = 0x[format %04X [expr {$tp_tail & 0xFFFF}]]   (bit15=按下 bit14=有按键)"
puts "tp_dev.touchtype               = 0x[format %02X [expr {($tp_tail >> 16) & 0xFF}]]   (bit0=横屏 bit7=电容屏)"

catch {con}
puts done
