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
#  4) 冷启动时 DAP 会停在错误态，必须先解锁；但**解锁用的 `rst -system` 之后要留足时间**，
#     否则紧跟的 ps7_init 会在 DDR 寄存器（0xF8006078）报
#       "Memory read error ... Blocked address ... Access can hang PS interconnect"
#     （实测：同一地址在 DAP 稳定后、任何复位方式下都读得通，当前值 0x00455111）。
#     所以这里把 ps7_init 包成「失败→系统复位→重试」的循环。
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
proc ensure_apu {} {
    if {[catch {targets -set -filter {name =~ "APU*"}} e]} {
        plog "APU target 不可见（$e），经 DAP 发系统复位解锁"
        catch {targets -set -filter {name =~ "DAP*"}}
        catch {rst -system}
        after 2500
        targets -set -filter {name =~ "APU*"}
        plog "DAP 已解锁，APU target 可见"
        return 1
    }
    return 0
}

# 探测 PS 寄存器是否可读（ps7_init 失败的先行指标）
proc ps_reg_readable {} {
    if {[catch {mrd -force 0xF8006078} v]} { return 0 }
    return 1
}

# 不管 DAP 是否健康，ps7_init 之前都必须把 PS 复位一次。
#   原因（实测踩到）：上一次烧的应用如果还在跑，它的 SCU 定时器和 GIC 使能位仍然有效。
#   直接盖上一遍 ps7_init 会把这套残留中断留给新应用 —— 新应用在 timer_init() 里注册
#   XIL_EXCEPTION_ID_INT *之前* 就吃到 IRQ，直接落到 Xil_ExceptionNullHandler
#   （实测 PC = 0x001a0d1c、CPSR 停在 IRQ 模式），显示通路一行都跑不到
#   （VDMA CR=0x00010002、VTC=0x00000000，画面里只剩被 ELF 覆盖一半的旧残像）。
#   现场对比：冷启动那次因 DAP 错误态已经复位过，所以正常；DAP 健康那次没复位，就中招。
if {[ensure_apu]} {
    after 1500
} else {
    catch {targets -set -filter {name =~ "DAP*"}}
    catch {rst -system}
    after 2500
    targets -set -filter {name =~ "APU*"}
}
if {[catch {fpga -file $bit_file} e]} { plog "fpga 失败: $e" } else { plog "PL 已配置" }

# ps7_init：DAP 刚复位完时可能还没稳，会以 "Blocked address" 报错中止；中途失败的 PS
# 处于半初始化态，必须整段重来。最多试 4 次。
set ps7_ok 0
for {set attempt 1} {$attempt <= 4} {incr attempt} {
    targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
    catch {stop}
    after 300
    if {![ps_reg_readable]} {
        plog "第 $attempt 次：0xF8006078 暂不可读，先系统复位"
        catch {targets -set -filter {name =~ "DAP*"}}
        catch {rst -system}
        after 3000
        ensure_apu
        after 1500
        continue
    }
    source $ps7_init
    if {![catch {ps7_init} e]} {
        if {![catch {ps7_post_config} e2]} {
            set ps7_ok 1
            plog "ps7 init 完成（第 $attempt 次）"
            break
        }
        plog "第 $attempt 次 ps7_post_config 失败: $e2"
    } else {
        plog "第 $attempt 次 ps7_init 失败: $e"
    }
    catch {targets -set -filter {name =~ "DAP*"}}
    catch {rst -system}
    after 3000
    ensure_apu
    after 1500
}
if {!$ps7_ok} { plog "ERROR: ps7_init 连续 4 次失败，中止"; close $::fh; return }

# 下载 ELF 前把核复位一次：清掉 CPSR 的 I 位（上一次应用可能留着中断使能）与残留挂起中断，
# 让新应用从复位状态起步。
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {rst -processor}
after 300
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
