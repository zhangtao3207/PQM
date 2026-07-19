# Recreate and build the PQM FreeRTOS SDK workspace from the exported HDF.
set script_dir [file dirname [file normalize [info script]]]
set arm_dir [file normalize [file join $script_dir ..]]
set repo_dir [file normalize [file join $arm_dir ..]]
set workspace_dir [file join $arm_dir sdk_workspace]
set hdf_file [file join $repo_dir FPGA export pqm_soc.hdf]
set app_sources [file join $arm_dir app src]

if {![file exists $hdf_file]} {
    error "PQM hardware handoff not found: $hdf_file"
}
if {[file exists $workspace_dir]} {
    file delete -force $workspace_dir
}
file mkdir $workspace_dir

setws $workspace_dir
createhw -name pqm_hw -hwspec $hdf_file
createbsp -name pqm_bsp -hwproject pqm_hw -proc ps7_cortexa9_0 \
    -os freertos10_xilinx
configbsp -bsp pqm_bsp use_malloc_failed_hook true
configbsp -bsp pqm_bsp check_for_stack_overflow 2
regenbsp -bsp pqm_bsp

createapp -name pqm_freertos -hwproject pqm_hw -proc ps7_cortexa9_0 \
    -os freertos10_xilinx -lang C -app {Empty Application} -bsp pqm_bsp
importsources -name pqm_freertos -path $app_sources
configapp -app pqm_freertos build-config release
projects -build -type all

set elf_file [file join $workspace_dir pqm_freertos Release pqm_freertos.elf]
if {![file exists $elf_file]} {
    error "PQM FreeRTOS ELF was not produced: $elf_file"
}
puts "Built PQM FreeRTOS application: $elf_file"
