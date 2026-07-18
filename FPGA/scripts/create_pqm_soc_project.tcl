# Recreate the PQM SoC project from repository sources.
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir [file normalize [file join $script_dir ..]]
set project_dir [file join $fpga_dir prj_soc]

proc collect_files {directory extension} {
    set result {}
    foreach entry [glob -nocomplain -directory $directory *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [collect_files $entry $extension]]
        } elseif {[string equal -nocase [file extension $entry] $extension]} {
            lappend result [file normalize $entry]
        }
    }
    return $result
}

if {[file exists $project_dir]} {
    file delete -force $project_dir
}
file mkdir $project_dir

create_project PQM_SOC $project_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [collect_files [file join $fpga_dir rtl] .v]
if {[llength $rtl_files] == 0} {
    error "No handwritten RTL found under [file join $fpga_dir rtl]"
}
add_files -norecurse $rtl_files

set xci_files [glob -nocomplain [file join $fpga_dir prj PQM.srcs sources_1 ip * *.xci]]
if {[llength $xci_files] != 0} {
    add_files -norecurse $xci_files
}

set constraints_file [file join $fpga_dir prj PQM.xdc]
if {![file exists $constraints_file]} {
    error "Constraints file not found: $constraints_file"
}
add_files -fileset constrs_1 -norecurse $constraints_file

source [file join $script_dir create_pqm_ps_bd.tcl]
set bd_file [get_files */pqm_ps.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

set_property top main [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Created reproducible PQM SoC project: [file join $project_dir PQM_SOC.xpr]"
close_project
