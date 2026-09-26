# 经 DAP 把 VDMA 正在扫描输出的帧缓存 dump 成文本，用于离线还原成图片。
#
# 运行：& xsct.bat scripts\dump_fb.tcl
#
# 官方比特流：frame_buffer_addr = XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x1000000
#            = 0x01100000，每像素 3 字节（RGB888），stride = 800*3 B，
#            总量 800*480*3 = 1152000 B = 288000 个 32 位字。

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set out_file   [file join $repo_dir export fb_dump.txt]

set base  0x01100000
set total 288000
set chunk 1024

connect
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}

# 停核再 dump：CPU 停下后界面不再刷新，读到的是一致的一帧。
if {[catch {stop} e]} { puts "stop: $e" }

set fh [open $out_file w]
set t0 [clock seconds]
set off 0
while {$off < $total} {
    set n $chunk
    if {[expr {$off + $n}] > $total} { set n [expr {$total - $off}] }
    set a [format 0x%08X [expr {$base + $off*4}]]
    if {[catch {mrd -force $a $n} line]} {
        puts "mrd 在 $a 失败：$line"
        break
    }
    puts $fh $line
    incr off $n
}
close $fh

puts "dump $off / $total 字，用时 [expr {[clock seconds]-$t0}] 秒 -> $out_file"
if {![catch {mrd -force 0x4300005C} v]} { puts "VDMA MM2S 起始地址寄存器 = [string trim $v]" }
if {![catch {mrd -force 0x43000004} v]} { puts "VDMA SR = [string trim $v]" }
if {![catch {mrd -force 0x43C10004} v]} { puts "VTC 状态 = [string trim $v]" }

catch {con}
puts done
