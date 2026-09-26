# 从 xci 生成 xfft_0 的仿真源（只生成 simulation target，不做综合与实现）。
#
# 用法：
#   vivado -mode batch -source pl/scripts/gen_xfft_sim_model.tcl \
#          -log export/gen_xfft.log -journal export/gen_xfft.jou
#
# 前置事实：xci 是从旧工程拷来的，定制于 Vivado 2018.3。2022.2 的 IP 目录里同名 IP
# 的 revision 不同，因此该 IP 处于 "locked"（版本过期）状态，必须先 upgrade_ip 才能
# 生成任何 target。升级只改 IP 的版本元数据，用户参数由 Vivado 保留；脚本会把升级
# 前后的 PARAM_VALUE 快照各存一份到 export/，便于事后逐行比对。
#
# 生成物落在 pl/ip/xfft_0/（xci 所在目录），不使用也不写入旧工程。

set repoRoot [file normalize [file join [file dirname [info script]] .. ..]]
set xciPath  [file join $repoRoot pl ip xfft_0 xfft_0.xci]
set projDir  [file join $repoRoot pl sim ipgen]
set ipDir    [file join $repoRoot pl ip xfft_0]
set logDir   [file join $repoRoot export]

puts "repoRoot = $repoRoot"
puts "xciPath  = $xciPath"

if {![file exists $xciPath]} {
    error "找不到 xci：$xciPath"
}

file mkdir $projDir
file mkdir $logDir

# 记录用户参数快照（只取 PARAM_VALUE.*，MODELPARAM 是推导值不比对）
proc dump_params {srcFile outFile} {
    set fh [open $outFile w]
    foreach line [split [read [open $srcFile r]] "\n"] {
        if {[string first "PARAM_VALUE." $line] >= 0} {
            puts $fh [string trim $line]
        }
    }
    close $fh
    puts "参数快照 -> $outFile"
}

create_project -force xfftgen $projDir -part xc7z020clg400-2

read_ip $xciPath
set ip [get_ips xfft_0]
puts "IP        = $ip"
puts "PART      = [get_property PART $ip]"

dump_params $xciPath [file join $logDir xfft_params_before.txt]

set locked "?"
catch {set locked [get_property IS_LOCKED $ip]}
puts "IS_LOCKED = $locked"

# 旧版本定制的 IP 在 2022.2 里必须升级才能生成 target。
upgrade_ip $ip

set locked2 "?"
catch {set locked2 [get_property IS_LOCKED $ip]}
puts "升级后 IS_LOCKED = $locked2"
dump_params $xciPath [file join $logDir xfft_params_after.txt]

generate_target {simulation} $ip

puts "=== pl/ip/xfft_0 下生成出的文件 ==="
foreach f [glob -nocomplain -directory $ipDir -types f *] {
    puts "  [file tail $f]"
}
foreach d [glob -nocomplain -directory $ipDir -types d *] {
    puts "  [file tail $d]/"
}

puts "=== 仿真源候选（含 .v / .vhd） ==="
foreach f [glob -nocomplain -directory $ipDir -types f *.v *.vhd] {
    puts "  $f"
}
foreach f [glob -nocomplain -directory [file join $ipDir xfft_0.gen] -types f *.v *.vhd] {
    puts "  $f"
}

close_project
puts "DONE"
