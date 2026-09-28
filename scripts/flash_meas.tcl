# ============================================================================
# 烧录 PQM2 测量版（pqm2_meas.xsa 编出的 bit + ELF），并用 JTAG 把 PS/PL 共享内存
# 抓成文本（每行 "字索引 十六进制值"），供 scripts/report_shm.ps1 解析。
#
# 运行（xsdb，工作目录不限）：
#   D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat C:\Users\zhangtao\Desktop\PQM2\scripts\flash_meas.tcl
#
# 踩过的三个点：
#  1) 读 PL 从设备前要把 target 切到 **APU**：
#       - 停在 ARM Cortex-A9 MPCore #N 上读 PL 地址会被 DAP 挡住，报
#           "Blocked address 0x40000000. PL AXI slave ports access is not allowed."
#       - 切到 APU（CPU 保持 Running）后 0x40000000 正常读到 50514D31。
#     另外 `-address-space AP0` 只在 APU target 上合法（Cortex-A9 target 上只有 PA）。
#     对照实验：scripts/probe_pl_read.tcl。
#  2) **不能用 `mrd -bin -file` 批量 dump**：同一地址上单字/多字 mrd 都正常，
#     唯独 `-bin -file` 会被同一句 "PL AXI slave ports access is not allowed" 挡掉。
#     对照实验：scripts/probe_mrd_count.tcl（count=1/2/4/16/64 全 OK，-bin 全 FAIL）。
#     所以这里用 64 字一拍的 `mrd -force <addr> <n>`，自己解析 "addr: value" 行。
#  3) 抓两次（间隔 1 秒）：两个计数器必须推进，否则说明读到的不是活数据。
# ============================================================================
set repo_dir {C:/Users/zhangtao/Desktop/PQM2}
set bit_file [file join $repo_dir build vitis_ws_meas pqm2_hw hw pqm2_meas.bit]
set ps7_init [file join $repo_dir build vitis_ws_meas pqm2_hw hw ps7_init.tcl]
set elf_file [file join $repo_dir build vitis_ws_meas pqm2_app Debug pqm2_app.elf]
set words1   [file join $repo_dir export shm_words_1.txt]
set words2   [file join $repo_dir export shm_words_2.txt]
set ::fh [open [file join $repo_dir export board_meas.log] w]
fconfigure $::fh -encoding utf-8 -translation lf
proc plog {m} { puts $m; catch { puts $::fh $m; flush $::fh } }
proc rd {a} { if {[catch {mrd -force $a} v]} { return ERR }; return [string trim [lindex [split $v ":"] end]] }

foreach r [list $bit_file $ps7_init $elf_file] {
    if {![file exists $r]} { plog "ERROR missing $r"; close $::fh; return }
}
plog "bit:  [file size $bit_file] B  $bit_file"
plog "elf:  [file size $elf_file] B  $elf_file"

# 抓整块共享内存：逐 64 字读，写 "word_index hex"。
proc dump_shm {path} {
    set base  0x40000000
    set total 16384
    set chunk 64
    set index 0
    set fh [open $path w]
    fconfigure $fh -encoding ascii -translation lf
    while {$index < $total} {
        set n $chunk
        if {$index + $n > $total} { set n [expr {$total - $index}] }
        set addr [format 0x%08X [expr {$base + $index * 4}]]
        if {[catch {mrd -force $addr $n} out]} {
            close $fh
            return "FAIL@word$index: $out"
        }
        set got 0
        foreach line [split $out "\n"] {
            set line [string trim $line]
            if {$line eq ""} { continue }
            set colon [string first ":" $line]
            if {$colon < 0} { continue }
            set val [string trim [string range $line [expr {$colon + 1}] end]]
            if {[string range $val 0 1] eq "0x"} { set val [string range $val 2 end] }
            if {$val eq ""} { continue }
            puts $fh "$index $val"
            incr index
            incr got
        }
        if {$got == 0} { close $fh; return "PARSE-EMPTY@word$index" }
    }
    close $fh
    return "OK $total words"
}

connect

# 冷启动（板子刚上电）时 DAP 可能停在错误态：
#   DAP (AHB AP transaction error, DAP status 0x30000021)
# 此时 APU target 不可见、直接 targets -set APU* 会 "no targets found"。
# 恢复办法：先在 DAP 上发一次系统复位把 DAP 解锁，APU/Cortex-A9 就会回来。
if {[catch {targets -set -filter {name =~ "APU*"}} e]} {
    plog "APU target 不可见（$e），经 DAP 发系统复位解锁"
    catch {targets -set -filter {name =~ "DAP*"}}
    catch {rst -system}
    after 1500
    targets -set -filter {name =~ "APU*"}
    plog "DAP 已解锁，APU target 可见"
}
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

plog "等待 10 秒（测量间隔 16e6 拍 @50 MHz = 0.32 s，谐波帧要跑几帧才稳定）..."
after 10000

# 关键：切到 APU target 再读，否则读 PL 地址会被挡掉。
targets -set -filter {name =~ "APU*"}
plog "target 已切到 APU（读 PL 从设备的通道），CPU 保持 Running"

plog "---- 显示通路寄存器（与官方基线逐项对照）----"
plog "  axi_gpio  0x41200000 = [rd 0x41200000]"
plog "  clk_wiz_0 0x43C00000 = [rd 0x43C00000]"
plog "  vdma CR   0x43000000 = [rd 0x43000000]"
plog "  vdma SR   0x43000004 = [rd 0x43000004]"
plog "  vdma addr 0x4300005C = [rd 0x4300005C]"
plog "  v_tc st   0x43C10004 = [rd 0x43C10004]"
plog "  参考(官方基线能出画面): CR=0001400B SR=00011000 addr=01100000 vtc=00013000"
plog "  共享内存 magic 0x40000000 = [rd 0x40000000]  (应为 50514D31)"

plog "---- 共享内存抓取 #1 ----"
plog "  [dump_shm $words1]  -> $words1"

after 1000
plog "---- 共享内存抓取 #2（1 秒后）----"
plog "  [dump_shm $words2]  -> $words2"

plog "=== done ==="
close $::fh
