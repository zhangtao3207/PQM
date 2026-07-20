# Recreate the PQM SoC project from repository sources.
set script_dir [file dirname [file normalize [info script]]]
if {[info exists ::env(PQM_REPO_ROOT)]} {
    set fpga_dir [file join $::env(PQM_REPO_ROOT) FPGA]
} else {
    set fpga_dir [file normalize [file join $script_dir ..]]
}
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
set_property include_dirs [list [file join $fpga_dir rtl PSInterface]] [get_filesets sources_1]

set xci_files [glob -nocomplain [file join $fpga_dir ip * *.xci]]
if {[llength $xci_files] != 0} {
    set copied_xci {}
    set imported_ip_dir [file join $project_dir PQM_SOC.srcs sources_1 ip]
    foreach source_xci $xci_files {
        set ip_name [file rootname [file tail $source_xci]]
        set target_dir [file join $imported_ip_dir $ip_name]
        set target_xci [file join $target_dir [file tail $source_xci]]
        file mkdir $target_dir
        file copy -force $source_xci $target_xci
        lappend copied_xci $target_xci
    }
    add_files -norecurse $copied_xci
    set_property generate_synth_checkpoint false [get_files $copied_xci]
    generate_target all [get_ips]
}

set constraints_file [file join $fpga_dir data PQM.xdc]
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
