# 诊断：ps7_init 在 0xF8006078 被 "Blocked address" 挡住的原因。
# 逐 target、逐复位方式试读同一个 PS 寄存器，找出能读通的那一种。
# 运行：& 'D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat' scripts\probe_ps_access.tcl

proc try_rd {label addr} {
    if {[catch {mrd -force $addr} v]} {
        puts "  $label  $addr -> FAIL: [string map {"\n" " "} $v]"
        return 0
    }
    puts "  $label  $addr -> [string trim [lindex [split $v ":"] end]]"
    return 1
}

connect
puts "=== targets ==="
foreach t [targets] { puts "  $t" }

puts "=== A. 当前状态下读 PS 寄存器（Cortex-A9 #0）==="
catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
catch {stop}
try_rd "A9#0 " 0xF8000000
try_rd "A9#0 " 0xF8006078
try_rd "A9#0 " 0xF8000120

puts "=== B. 在 APU 上读同一批 ==="
catch {targets -set -filter {name =~ "APU*"}}
try_rd "APU  " 0xF8000000
try_rd "APU  " 0xF8006078

puts "=== C. rst -processor 之后再读 ==="
catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
catch {rst -processor}
after 500
try_rd "A9#0 " 0xF8000000
try_rd "A9#0 " 0xF8006078

puts "=== D. rst -system 之后再读（等 2 秒）==="
catch {rst -system}
after 2000
catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
catch {stop}
try_rd "A9#0 " 0xF8000000
try_rd "A9#0 " 0xF8006078

puts "=== E. 重新 connect 之后再读 ==="
disconnect
after 1000
connect
catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}
catch {stop}
try_rd "A9#0 " 0xF8000000
try_rd "A9#0 " 0xF8006078
catch {con}
puts "=== done ==="
exit
