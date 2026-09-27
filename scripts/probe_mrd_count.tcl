# 探测：在 APU target 上，0x40000000 处 单字 / 多字 mrd 哪种可用。
connect
targets -set -filter {name =~ "APU*"}
foreach n {1 2 4 16 64} {
    if {[catch {mrd -force 0x40000000 $n} v]} {
        puts "count=$n FAIL: $v"
    } else {
        puts "count=$n OK:"
        foreach line [split $v "\n"] { if {[string trim $line] ne ""} { puts "    [string trim $line]" } }
    }
}
puts "=== -bin 单字 ==="
if {[catch {mrd -bin -file C:/Users/zhangtao/Desktop/PQM2/export/probe1.bin 0x40000000 1} v]} { puts "FAIL: $v" } else { puts "OK: $v" }
puts "=== done ==="
