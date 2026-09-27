# 探测 JTAG 能不能读 PL 从设备地址（特别是共享内存 0x40000000）。
# 现象：flash_meas.tcl 里 0x43000000 等地址能读，0x40000000 报
#   "Blocked address ... PL AXI slave ports access is not allowed"。
# 这里把各种访问方式都试一遍，找出可用的那一种。
proc try {label script} {
    if {[catch {uplevel 1 $script} v]} {
        puts "  [format %-34s $label] FAIL: $v"
    } else {
        puts "  [format %-34s $label] OK  : $v"
    }
}

connect
puts "=== 当前 target 列表 ==="
puts [targets]
try "set APU" { targets -set -filter {name =~ "APU*"} }
puts "  state = [state]"

puts "=== 默认访问（与 flash_meas.tcl 相同）==="
try "DDR 0x00100000"       { mrd -force 0x00100000 }
try "BRAM 0x40000000"      { mrd -force 0x40000000 }
try "BRAM 0x40001000"      { mrd -force 0x40001000 }
try "gpio 0x41200000"      { mrd -force 0x41200000 }
try "vdma 0x43000000"      { mrd -force 0x43000000 }
try "vtc  0x43C10000"      { mrd -force 0x43C10000 }

puts "=== 用 -address-space 指定访问端口 ==="
foreach sp {AP0 AP1 AP2 APB AXI} {
    try "AS $sp BRAM 0x40000000" [list mrd -force -address-space $sp 0x40000000]
    try "AS $sp vdma 0x43000000" [list mrd -force -address-space $sp 0x43000000]
}

puts "=== 换其它 target 再读 ==="
foreach t {"APU*" "*Cortex-A9*#0" "*DAP*" "*APB*"} {
    if {[catch {targets -set -nocase -filter [list name =~ $t]} e]} {
        puts "  target $t: 无法选择 ($e)"
        continue
    }
    puts "  --- target = $t ---"
    try "  $t BRAM" { mrd -force 0x40000000 }
    try "  $t vdma" { mrd -force 0x43000000 }
}

puts "=== done ==="
