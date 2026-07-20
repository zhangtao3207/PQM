# Synthesize both the PS-display and legacy-display PQM top-level modes.

set script_dir [file dirname [file normalize [info script]]]
if {[info exists ::env(PQM_REPO_ROOT)]} {
    set fpga_dir [file join $::env(PQM_REPO_ROOT) FPGA]
} else {
    set fpga_dir [file normalize [file join $script_dir ..]]
}
set project_file [file join $fpga_dir prj_soc PQM_SOC.xpr]
set report_dir [file join $fpga_dir reports top_modes]

if {![file exists $project_file]} {
    error "PQM SoC project does not exist: $project_file"
}

open_project $project_file
set_property top main [get_filesets sources_1]
file mkdir $report_dir

set modes {0 1}
if {[info exists ::env(PQM_TOP_MODES)]} {
    set modes [split $::env(PQM_TOP_MODES) ","]
}

foreach legacy_mode $modes {
    puts "INFO: synthesizing main with LEGACY_PL_DISPLAY=$legacy_mode"
    set_property generic [list LEGACY_PL_DISPLAY=$legacy_mode] [get_filesets sources_1]
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    set synth_status [get_property STATUS [get_runs synth_1]]
    if {![string match {*Complete*} $synth_status]} {
        error "Top mode $legacy_mode synthesis failed: $synth_status"
    }
    open_run synth_1
    report_utilization \
        -file [file join $report_dir "utilization_synth_mode_${legacy_mode}.rpt"]
    report_utilization -hierarchical -hierarchical_depth 8 \
        -file [file join $report_dir "utilization_hier_mode_${legacy_mode}.rpt"]
    report_timing_summary \
        -file [file join $report_dir "timing_synth_mode_${legacy_mode}.rpt"]
    close_design
}

puts "PQM_TOP_MODE_CHECK_PASS"
close_project
