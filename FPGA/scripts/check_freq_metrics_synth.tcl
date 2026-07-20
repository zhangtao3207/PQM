# Synthesize the frequency raw-metrics block and reject inferred timing loops.

set script_dir [file dirname [file normalize [info script]]]
if {[info exists ::env(PQM_REPO_ROOT)]} {
    set fpga_dir [file join $::env(PQM_REPO_ROOT) FPGA]
} else {
    set fpga_dir [file normalize [file join $script_dir ..]]
}
set basic_math_dir [file join $fpga_dir rtl DataProcessor BasicMath]
set raw_calc_dir [file join $fpga_dir rtl DataProcessor SignalProcessing FreqAnalysis RawDataCal]

create_project freq_metrics_synth_check -in_memory -part xc7z020clg400-2
add_files [list \
    [file join $basic_math_dir divider_unsigned.v] \
    [file join $basic_math_dir multiplier_signed.v] \
    [file join $basic_math_dir sqrt_unsigned.v] \
    [file join $raw_calc_dir freq_thd_raw_calc.v] \
    [file join $raw_calc_dir freq_metrics_raw_calc.v]]
set_property top freq_metrics_raw_calc [get_filesets sources_1]
set_msg_config -id {Synth 8-295} -new_severity ERROR
synth_design -top freq_metrics_raw_calc -part xc7z020clg400-2 -name freq_metrics_synth_check
set accumulator_dsps [get_cells -quiet -hierarchical -filter {REF_NAME =~ "DSP48*" && NAME =~ "*square_sum_work*"}]
if {[llength $accumulator_dsps] != 0} {
    error "Square-sum accumulators still mapped to DSP48: $accumulator_dsps"
}
puts "PQM_FREQ_METRICS_SYNTH_CHECK_PASS"
close_design
close_project
