# 连续抓谐波表的第 1 页（H0..H15），两个 bank 都抓，用来量化相位到底有多不稳。
# 输出 export/phase_trace.txt，每行：
#   S <样本号> <harm_gen> <status>
#   B <样本号> <bank> <order> <u_ratio_x100> <i_ratio_x100> <phase_x100> <flags>
# 运行：& 'D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat' scripts\trace_phase.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set out_file   [file join $repo_dir export phase_trace.txt]

proc rdw {addr count} {
    if {[catch {mrd -force $addr $count} out]} { return {} }
    set vals {}
    foreach line [split $out "\n"] {
        set line [string trim $line]
        if {$line eq ""} { continue }
        set c [string first ":" $line]
        if {$c < 0} { continue }
        lappend vals [string trim [string range $line [expr {$c + 1}] end]]
    }
    return $vals
}

proc hex2int {h} {
    set h [string trim $h]
    if {[string range $h 0 1] eq "0x"} { set h [string range $h 2 end] }
    if {$h eq ""} { return 0 }
    # 32 位无符号 -> 有符号
    set v 0
    foreach ch [split $h ""] {
        set d [string first $ch "0123456789abcdefABCDEF"]
        if {$d < 0} { continue }
        if {$d > 15} { set d [expr {$d - 6}] }
        set v [expr {(($v << 4) | $d) & 0xFFFFFFFF}]
    }
    if {$v >= 0x80000000} { set v [expr {$v - 0x100000000}] }
    return $v
}

connect
targets -set -filter {name =~ "APU*"}

set fh [open $out_file w]
fconfigure $fh -encoding ascii -translation lf

# 0x40000000 + word*4：status 是 word 2、harm_gen 是 word 4
set samples 24
for {set i 0} {$i < $samples} {incr i} {
    set st  [lindex [rdw 0x40000008 1] 0]
    set gen [lindex [rdw 0x40000010 1] 0]
    puts $fh "S $i [hex2int $gen] [hex2int $st]"

    # bank0 首 16 条：word 0x400 起，16*4 = 64 字；bank1：word 0xC00 起
    foreach {bank base} {0 0x40001000 1 0x40003000} {
        set w [rdw $base 64]
        for {set e 0} {$e < 16} {incr e} {
            set o [expr {$e * 4}]
            if {[llength $w] < [expr {$o + 4}]} { continue }
            puts $fh "B $i $bank $e [hex2int [lindex $w $o]] [hex2int [lindex $w [expr {$o+1}]]] [hex2int [lindex $w [expr {$o+2}]]] [hex2int [lindex $w [expr {$o+3}]]]"
        }
    }
    after 200
}
close $fh
puts "wrote $out_file"
exit
