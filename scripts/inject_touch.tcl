# 经 JTAG 注入一次触摸点击（按下 -> 松开），用来在没有手指的情况下切页、按按钮。
#
# 运行：& xsdb.bat scripts\inject_touch.tcl <屏幕x> <屏幕y>
#
# 原理：
#   app\port\lv_port_indev.c 的 touchpad_is_pressed() 每次都先调 tp_dev.scan() 再读
#   tp_dev.sta，所以直接写 sta 会被立刻覆盖。这里先把函数指针 tp_dev.scan 临时指到
#   Xil_DCacheFlush()（无参数、无副作用、应用本来就每 5 ms 调它一次），扫描就变成空操作，
#   注入的 sta/x/y 得以保留；点完再把函数指针和 sta 都还原。
#
# 踩过的点：
#   1) tp_dev 结构体布局（app\TOUCH\touch.h）：
#        +0  init(u32)  +4 scan(u32)  +8 x[10](u16)  +28 y[10](u16)  +48 sta(u16)  +50 touchtype(u8)
#      x/y 用 32 位字写会连带写 x[1]/y[1]，单点触摸下无害；sta 那个字的高 16 位是
#      touchtype（bit0=横屏 bit7=电容屏），必须读-改-写，不能整体覆盖。
#   2) 注入的是**屏幕坐标**（tp_dev.x/y 存的就是扫描时换算好的屏幕坐标，
#      lv_port_indev 直接把它交给 LVGL，不再做任何翻转）。
#   3) 下面的地址来自构建产物，**每次重新编译都会变**，重新取法：
#        arm-none-eabi-nm -S build\vitis_ws_meas\pqm2_app\Debug\pqm2_app.elf | findstr /R " tp_dev Xil_DCacheFlush FT5206_Scan"

set TP_DEV      0x001e67b8   ;# tp_dev
set STUB_SCAN   0x001a0c6c   ;# Xil_DCacheFlush
set REAL_SCAN   0x00106ca0   ;# FT5206_Scan

set tx 0
set ty 0
if {[llength $argv] >= 2} {
    set tx [lindex $argv 0]
    set ty [lindex $argv 1]
} else {
    puts "用法：xsdb.bat scripts\\inject_touch.tcl <屏幕x> <屏幕y>"
    exit 1
}

proc rd {addr} {
    if {[catch {mrd -force $addr} v]} { return -1 }
    set text [string trim [lindex [split $v ":"] end]]
    if {[string range $text 0 1] eq "0x"} { set text [string range $text 2 end] }
    if {![string is xdigit -strict $text]} { return -1 }
    return [scan $text %x]
}

proc wr {addr value} {
    if {[catch {mwr -force $addr $value} e]} { puts "  mwr 0x[format %08X $addr] 失败: $e" }
}

connect
targets -set -filter {name =~ "APU*"}

set init_addr  $TP_DEV
set scan_addr  [expr {$TP_DEV + 4}]
set x_addr     [expr {$TP_DEV + 8}]
set y_addr     [expr {$TP_DEV + 28}]
set sta_addr   [expr {$TP_DEV + 48}]

set old_scan [rd $scan_addr]
set sta_word [rd $sta_addr]
puts "tp_dev.init = 0x[format %08X [rd $init_addr]]"
puts "tp_dev.scan = 0x[format %08X $old_scan]  (0x[format %08X $REAL_SCAN] = FT5206_Scan)"
puts "tp_dev.sta  = 0x[format %04X [expr {$sta_word & 0xFFFF}]]  touchtype = 0x[format %02X [expr {($sta_word >> 16) & 0xFF}]]"

# 1) 扫描变空操作，注入坐标 + 按下
wr $scan_addr $STUB_SCAN
wr $x_addr [expr {$tx | ($tx << 16)}]
wr $y_addr [expr {$ty | ($ty << 16)}]
wr $sta_addr [expr {($sta_word & 0xFFFF0000) | 0xC001}]
puts "按下 ($tx, $ty)"
after 400

# 2) 松开（LVGL 在松开时才会派发 LV_EVENT_CLICKED）
wr $sta_addr [expr {$sta_word & 0xFFFF0000}]
puts "松开"
after 400

# 3) 还原：触摸扫描交回 FT5206，sta 复位
wr $scan_addr $REAL_SCAN
wr $sta_addr $sta_word
puts "已还原 tp_dev.scan = 0x[format %08X [rd $scan_addr]]  sta = 0x[format %04X [expr {[rd $sta_addr] & 0xFFFF}]]"
puts done
exit
