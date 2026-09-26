# 烧录并运行 PQM2：系统复位 -> 编程 PL -> 上电 PS -> 下载 ELF -> 回读校验 -> 运行。
#
# 运行：& xsct.bat scripts\flash_and_run.tcl
#
# 说明：
#   * 编程前必须先做一次系统复位。上一轮应用若已开启 MMU，dow 会以
#     "Memory write error ... MMU section translation fault" 失败。
#   * 回读校验用 VDMA/VTC 寄存器与帧缓存内容，而不是只看 dow 的返回值。

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set bit_file   [file join $repo_dir build vitis_ws pqm2_hw hw system_wrapper.bit]
set ps7_init   [file join $repo_dir build vitis_ws pqm2_hw hw ps7_init.tcl]
set elf_file   [file join $repo_dir build vitis_ws pqm2_app Debug pqm2_app.elf]
set log_file   [file join $repo_dir export flash.log]

file mkdir [file dirname $log_file]
set ::fh [open $log_file w]
fconfigure $::fh -encoding utf-8 -translation lf

proc plog {msg} {
    puts $msg
    catch {
        puts $::fh $msg
        flush $::fh
    }
}

proc rd {addr} {
    if {[catch {mrd -force $addr} v]} { return "ERR" }
    return [string trim [lindex [split $v ":"] end]]
}

foreach required [list $bit_file $ps7_init $elf_file] {
    if {![file exists $required]} {
        plog "ERROR: missing $required"
        close $::fh
        return
    }
}

plog "bit : [file tail $bit_file]  [file size $bit_file] B"
plog "elf : [file tail $elf_file]  [file size $elf_file] B"

connect

plog "=== 1. 系统复位 ==="
targets -set -filter {name =~ "APU*"}
if {[catch {rst -system} e]} { plog "rst -system: $e" }
after 1000

plog "=== 2. 编程 PL ==="
if {[catch {fpga -file $bit_file} e]} { plog "fpga 失败: $e" } else { plog "PL 已配置" }

plog "=== 3. PS 上电 ==="
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
catch {stop}
source $ps7_init
ps7_init
ps7_post_config
plog "ps7_init + ps7_post_config 完成"

plog "=== 4. PL 侧身份校验（官方比特流才有这些值）==="
plog "  axi_gpio_0 0x41200000 = [rd 0x41200000]"
plog "  axi_vdma_0 0x43000000 = [rd 0x43000000]"
plog "  clk_wiz_0  0x43C00000 = [rd 0x43C00000]"
plog "  v_tc_0     0x43C10000 = [rd 0x43C10000]"

plog "=== 5. 下载 ELF ==="
if {[catch {dow $elf_file} e]} {
    plog "dow 失败: $e"
} else {
    plog "ELF 已下载"
}

plog "=== 6. 运行 ==="
if {[catch {con} e]} { plog "con: $e" }
after 3000

plog "=== 7. 运行后回读（读寄存器时短暂停核）==="
if {[catch {stop} e]} { plog "stop: $e" }
plog "  vdma CR   0x43000000 = [rd 0x43000000]"
plog "  vdma SR   0x43000004 = [rd 0x43000004]"
plog "  vdma addr 0x4300005C = [rd 0x4300005C]"
plog "  axi_gpio  0x41200000 = [rd 0x41200000]"
plog "  v_tc stat 0x43C10004 = [rd 0x43C10004]"
plog "  --- VDMA SR 位：0=Halted 1=Idle 12=IOC_Irq ---"
plog "  --- 参考：官方例程跑通时 SR=0x00011000, MM2S 起始=0x01100000, VTC=0x00013000 ---"

plog "=== 8. 恢复运行 ==="
catch {con}

plog "=== done ==="
close $::fh
