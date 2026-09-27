set repo_dir   {C:/Users/zhangtao/Desktop/PQM2}
set bit_file   [file join $repo_dir vivado system.bit]
set ps7_init   [file join $repo_dir build vitis_ws pqm2_hw hw ps7_init.tcl]
set elf_file   [file join $repo_dir build vitis_ws pqm2_app Debug pqm2_app.elf]
set ::fh [open [file join $repo_dir export board_run.log] w]
fconfigure $::fh -encoding utf-8 -translation lf
proc plog {m} { puts $m; catch { puts $::fh $m; flush $::fh } }
proc rd {a} { if {[catch {mrd -force $a} v]} { return ERR }; return [string trim [lindex [split $v ":"] end]] }

plog "=== connect ==="
connect
plog "=== 1. 系统复位 ==="
targets -set -filter {name =~ "APU*"}
catch {rst -system}
after 1000
plog "=== 2. 编程 PL ==="
if {[catch {fpga -file $bit_file} e]} { plog "fpga 失败: $e" } else { plog "PL 已配置" }
plog "=== 3. PS 上电 ==="
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {stop}
source $ps7_init
ps7_init
ps7_post_config
plog "ps7 init 完成"
plog "=== 4. 下载 ELF ==="
if {[catch {dow $elf_file} e]} { plog "dow 失败: $e" } else { plog "ELF 已下载" }
plog "=== 5. 运行并等待 app 初始化 ==="
catch {con}
plog "  等待 10 秒..."
after 10000
plog "=== 6. 回读（确认 app 是否配置了 VDMA/VTC）==="
catch {stop}
plog "  vdma CR   0x43000000 = [rd 0x43000000]"
plog "  vdma SR   0x43000004 = [rd 0x43000004]"
plog "  vdma addr 0x4300005C = [rd 0x4300005C]"
plog "  v_tc      0x43C10000 = [rd 0x43C10000]"
plog "  v_tc st   0x43C10004 = [rd 0x43C10004]"
plog "  参考(09-26 成功): CR=0001400B SR=00011000 addr=01100000 vtc=00013000"
catch {con}
plog "=== done ==="
close $::fh
