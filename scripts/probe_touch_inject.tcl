# 触摸注入的排查：确认 tp_dev.scan / sta 的写入是否真的落地、是否被应用改回。
# 运行：& xsdb.bat scripts\probe_touch_inject.tcl

set TP_DEV      0x001e6878
set STUB_SCAN   0x001a0d2c
set REAL_SCAN   0x00106d60

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

set ini_addr [expr {$TP_DEV + 0}]
set scn_addr [expr {$TP_DEV + 4}]
set x_addr   [expr {$TP_DEV + 8}]
set y_addr   [expr {$TP_DEV + 28}]
set sta_addr [expr {$TP_DEV + 48}]

connect
targets -set -filter {name =~ "APU*"}

set orig_scan [rd $scn_addr]
set orig_sta  [rd $sta_addr]
puts "原始：init=0x[format %08X [rd $ini_addr]] scan=0x[format %08X $orig_scan] sta=0x[format %04X [expr {$orig_sta & 0xFFFF}]] touchtype=0x[format %02X [expr {($orig_sta >> 16) & 0xFF}]]"

puts "--- 写 stub 到 tp_dev.scan ---"
wr $scn_addr $STUB_SCAN
puts "  立即读回 = 0x[format %08X [rd $scn_addr]]"
after 500
puts "  500ms 后 = 0x[format %08X [rd $scn_addr]]   (若变回 0x00106D60 说明应用改写了它)"

puts "--- 写坐标 + 按下 ---"
wr $x_addr [expr {611 | (611 << 16)}]
wr $y_addr [expr {22 | (22 << 16)}]
wr $sta_addr [expr {($orig_sta & 0xFFFF0000) | 0xC001}]
foreach t {0 200 400 800} {
    after 200
    puts "  ${t}ms: x[0]=[expr {[rd $x_addr] & 0xFFFF}] y[0]=[expr {[rd $y_addr] & 0xFFFF}] sta=0x[format %04X [expr {[rd $sta_addr] & 0xFFFF}]]"
}

puts "--- 松开 ---"
wr $sta_addr [expr {$orig_sta & 0xFFFF0000}]
after 300
puts "  sta=0x[format %04X [expr {[rd $sta_addr] & 0xFFFF}]]"

puts "--- 还原 ---"
wr $scn_addr $orig_scan
wr $sta_addr $orig_sta
puts "  scan=0x[format %08X [rd $scn_addr]] sta=0x[format %04X [expr {[rd $sta_addr] & 0xFFFF}]]"
puts done
exit
