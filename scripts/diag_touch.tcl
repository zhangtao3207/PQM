# 只读诊断：把触摸相关的全局量从运行中的板子上读出来。
#
# 运行：& xsct.bat scripts\diag_touch.tcl
#
# 注意：这个脚本会停核读内存，运行期间应用里的触摸轮询会被打断，
# 所以不要一边跑它一边试触摸。
#
# 下面的地址来自构建产物，**每次重新编译都会变**，重新取法：
#   arm-none-eabi-nm -S build\vitis_ws\pqm2_app\Debug\pqm2_app.elf | findstr /R "lcd_id tp_dev"
# 然后更新下面 set 的四个值（本脚本按当前 ELF：lcd_id=0x00468304，tp_dev=0x001E5220）。

set lcd_id_addr 0x00468304
set tp_dev_addr 0x001E5220

connect
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
if {[catch {stop} e]} { puts "stop: $e" }

proc rdw {addr} {
    if {[catch {mrd -force $addr} v]} { return -1 }
    set text [string trim [lindex [split $v ":"] end]]
    if {![string is xdigit -strict $text]} { return -1 }
    return [scan $text %x]
}

set lcd_id  [rdw $lcd_id_addr]
set tp_init [rdw $tp_dev_addr]
set tp_scan [rdw [expr {$tp_dev_addr + 4}]]
set tp_x    [rdw [expr {$tp_dev_addr + 8}]]
set tp_y    [rdw [expr {$tp_dev_addr + 28}]]
set tp_tail [rdw [expr {$tp_dev_addr + 48}]]

puts "lcd_id            = 0x[format %08X $lcd_id]   (0x7084 = 7 寸 800x480，会走 FT5206_Init)"
puts "tp_dev.init       = 0x[format %08X $tp_init]"
puts "tp_dev.scan       = 0x[format %08X $tp_scan]"
puts "    TP_Scan     = 0x00107548  默认值，说明 TP_Init 没选中任何控制器"
puts "    FT5206_Scan = 0x001057A0"
puts "    GT9147_Scan = 0x00106398"
puts "tp_dev.x[0]       = [expr {$tp_x & 0xFFFF}]"
puts "tp_dev.y[0]       = [expr {$tp_y & 0xFFFF}]"
puts "tp_dev.sta        = 0x[format %04X [expr {$tp_tail & 0xFFFF}]]   bit15=按下 bit14=有按键"
puts "tp_dev.touchtype  = 0x[format %02X [expr {($tp_tail >> 16) & 0xFF}]]   bit0=横屏 bit7=电容屏"

catch {con}
puts done
