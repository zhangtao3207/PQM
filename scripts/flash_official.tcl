# 烧录官方基线（official_base.xsa 编出的那套 bit + ELF）。
set repo_dir {C:/Users/zhangtao/Desktop/PQM2}
set bit_file [file join $repo_dir build vitis_ws_official pqm2_hw hw official_base.bit]
set ps7_init [file join $repo_dir build vitis_ws_official pqm2_hw hw ps7_init.tcl]
set elf_file [file join $repo_dir build vitis_ws_official pqm2_app Debug pqm2_app.elf]
set ::fh [open [file join $repo_dir export board_official.log] w]
fconfigure $::fh -encoding utf-8 -translation lf
proc plog {m} { puts $m; catch { puts $::fh $m; flush $::fh } }
proc rd {a} { if {[catch {mrd -force $a} v]} { return ERR }; return [string trim [lindex [split $v ":"] end]] }

foreach r [list $bit_file $ps7_init $elf_file] { if {![file exists $r]} { plog "ERROR missing $r"; close $::fh; return } }
plog "bit: [file size $bit_file] B"
plog "elf: [file size $elf_file] B"
connect
targets -set -filter {name =~ "APU*"}
catch {rst -system}
after 1000
if {[catch {fpga -file $bit_file} e]} { plog "fpga 失败: $e" } else { plog "PL 已配置" }
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {stop}
source $ps7_init
ps7_init
ps7_post_config
plog "ps7 init 完成"
if {[catch {dow $elf_file} e]} { plog "dow 失败: $e" } else { plog "ELF 已下载" }
catch {con}
plog "等待 8 秒..."
after 8000
catch {stop}
plog "  axi_gpio  0x41200000 = [rd 0x41200000]"
plog "  clk_wiz_0 0x43C00000 = [rd 0x43C00000]"
plog "  vdma CR   0x43000000 = [rd 0x43000000]"
plog "  vdma SR   0x43000004 = [rd 0x43000004]"
plog "  vdma addr 0x4300005C = [rd 0x4300005C]"
plog "  v_tc st   0x43C10004 = [rd 0x43C10004]"
plog "  参考(能出画面): CR=0001400B SR=00011000 addr=01100000 vtc=00013000"
catch {con}
plog "=== done ==="
close $::fh
