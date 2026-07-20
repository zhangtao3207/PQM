# Build the generated PQM SoC project and export hardware deliverables.
set script_dir [file dirname [file normalize [info script]]]
if {[info exists ::env(PQM_REPO_ROOT)]} {
    set fpga_dir [file join $::env(PQM_REPO_ROOT) FPGA]
} else {
    set fpga_dir [file normalize [file join $script_dir ..]]
}
set project_file [file join $fpga_dir prj_soc PQM_SOC.xpr]
set export_dir [file join $fpga_dir export]
set reports_dir [file join $export_dir reports]
set synth_pre_hook [file join $fpga_dir scripts vivado_synth_pre.tcl]

if {![file exists $project_file]} {
    error "PQM SoC project not found: $project_file"
}
file mkdir $reports_dir
open_project $project_file

reset_run synth_1
set_property STEPS.SYNTH_DESIGN.TCL.PRE $synth_pre_hook [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match {*Complete*} $synth_status]} {
    error "Synthesis failed: $synth_status"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match {*Complete*} $impl_status]} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
report_utilization -file [file join $reports_dir utilization_placed.rpt]
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $reports_dir utilization_hierarchical.rpt]
report_timing_summary -file [file join $reports_dir timing_summary.rpt]
set worst_setup_path [get_timing_paths -setup -max_paths 1]
if {[llength $worst_setup_path] == 0} {
    error "No routed setup timing path was reported"
}
set routed_wns [get_property SLACK $worst_setup_path]
puts "INFO: routed setup WNS = $routed_wns ns"
if {$routed_wns < 0.0} {
    error "Routed timing failed: WNS=$routed_wns ns"
}
write_bitstream -force [file join $export_dir pqm_soc.bit]
write_hwdef -force -file [file join $export_dir pqm_soc.hdf]
puts "Exported PQM SoC hardware to $export_dir"
close_project
