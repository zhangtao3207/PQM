# Recreate and build the PQM FreeRTOS SDK workspace from the exported HDF.
set script_dir [file dirname [file normalize [info script]]]
set arm_dir [file normalize [file join $script_dir ..]]
set repo_dir [file normalize [file join $arm_dir ..]]
set workspace_dir [file join $arm_dir sdk_workspace]
set hdf_file [file join $repo_dir FPGA export pqm_soc.hdf]
set app_sources [file join $arm_dir app src]
set lvgl_root [file join $arm_dir third_party lvgl]
set lvgl_sources [file join $arm_dir third_party lvgl src]

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

createapp -name pqm_freertos -hwproject pqm_hw -proc ps7_cortexa9_0 \
    -os freertos10_xilinx -lang C -app {Empty Application} -bsp pqm_bsp
importsources -name pqm_freertos -path $app_sources

# Reserve the top 32 MiB of DDR for fixed-address framebuffer storage.
set linker_file [file join $workspace_dir pqm_freertos src lscript.ld]
set linker_channel [open $linker_file r]
set linker_text [read $linker_channel]
close $linker_channel
set linker_text [string map {
    {ps7_ddr_0 : ORIGIN = 0x100000, LENGTH = 0x3FF00000}
    {ps7_ddr_0 : ORIGIN = 0x100000, LENGTH = 0x3DF00000}
} $linker_text]
set linker_channel [open $linker_file w]
puts -nonewline $linker_channel $linker_text
close $linker_channel

set app_include [file join $workspace_dir pqm_freertos src]
set lvgl_target [file join $app_include lvgl]
file mkdir $lvgl_target
file copy -force [file join $lvgl_root lvgl.h] [file join $lvgl_target lvgl.h]
file copy -force $lvgl_sources [file join $lvgl_target src]
configapp -app pqm_freertos build-config release
configapp -app pqm_freertos compiler-misc \
    "-I$app_include -I$lvgl_target -DLV_CONF_INCLUDE_SIMPLE"
projects -build -type all

set elf_file [file join $workspace_dir pqm_freertos Release pqm_freertos.elf]
if {![file exists $elf_file]} {
    error "PQM FreeRTOS ELF was not produced: $elf_file"
}
puts "Built PQM FreeRTOS application: $elf_file"
