# 新 ELF 下载后显示未启动：查 CPU 到底停在哪、外设寄存器是什么状态。
# 运行：& 'D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat' scripts\probe_app_state.tcl

proc rd {a} { if {[catch {mrd -force $a} v]} { return ERR }; return [string trim [lindex [split $v ":"] end]] }

connect
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
if {[catch {stop} e]} { puts "stop: $e" }
after 200

puts "---- CPU ----"
foreach r {pc cpsr r0 r1 r13} {
    if {[catch {rrd $r} v]} { puts "  $r = ERR" } else { puts "  $r = [string trim $v]" }
}

puts "---- 外设 ----"
puts "  axi_gpio 0x41200000 = [rd 0x41200000]"
puts "  gpio2    0x41200008 = [rd 0x41200008]"
puts "  clk_wiz  0x43C00000 = [rd 0x43C00000]"
puts "  vdma CR  0x43000000 = [rd 0x43000000]"
puts "  vdma SR  0x43000004 = [rd 0x43000004]"
puts "  vdma MM2S 0x4300005C = [rd 0x4300005C]"
puts "  vdma S2MM 0x430000AC = [rd 0x430000AC]"
puts "  v_tc     0x43C10000 = [rd 0x43C10000]"
puts "  v_tc st  0x43C10004 = [rd 0x43C10004]"

puts "---- 异常向量表（0x00000000 附近）----"
foreach a {0x00000000 0x00000008 0x00000010 0x00000018 0x00000020} {
    puts "  [format 0x%08X $a] = [rd $a]"
}

puts "---- 共享内存仍在推进吗 ----"
puts "  magic = [rd 0x40000000]  snap_seq = [rd 0x4000000C]"
after 1000
puts "  1s 后 snap_seq = [rd 0x4000000C]"

catch {con}
puts "done"
exit
