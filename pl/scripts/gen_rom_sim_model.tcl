set repoRoot [file normalize [file join [file dirname [info script]] .. ..]]
set ipDir    [file join $repoRoot pl ip rom_atan_lut_1024]
set projDir  [file join $repoRoot pl sim ipgen]
file mkdir $projDir
create_project -force romgen $projDir -part xc7z020clg400-2
read_ip [file join $ipDir rom_atan_lut_1024.xci]
set ip [get_ips rom_atan_lut_1024]
puts "IP        = $ip"
set lk "?"; catch {set lk [get_property IS_LOCKED $ip]}
puts "IS_LOCKED = $lk"
upgrade_ip $ip
set lk2 "?"; catch {set lk2 [get_property IS_LOCKED $ip]}
puts "升级后 IS_LOCKED = $lk2"
generate_target {simulation} $ip
puts "=== ip 目录生成物 ==="
foreach f [glob -nocomplain -directory $ipDir -types f *] { puts "  [file tail $f]" }
foreach d [glob -nocomplain -directory $ipDir -types d *] { puts "  [file tail $d]/" }
if {[file exists [file join $ipDir sim]]} {
  foreach f [glob -nocomplain -directory [file join $ipDir sim] -types f *] { puts "  sim/[file tail $f]" }
}
if {[file exists [file join $ipDir hdl]]} {
  foreach f [glob -nocomplain -directory [file join $ipDir hdl] -types f *] { puts "  hdl/[file tail $f]" }
}
close_project
puts DONE
