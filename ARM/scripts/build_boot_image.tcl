# Build a fresh Zynq FSBL from the current SDK hardware project.
if {![info exists ::env(PQM_REPO_ROOT)]} {
    error "PQM_REPO_ROOT is not set; use run_xsct.ps1"
}
set repo_dir $::env(PQM_REPO_ROOT)
set workspace_dir [file join $repo_dir ARM sdk_workspace]
set hardware_dir [file join $workspace_dir pqm_hw]
set bif_files [glob -nocomplain [file join $repo_dir FPGA * bootbin.bif]]
if {[llength $bif_files] != 1} {
    error "Expected one bootbin.bif under FPGA, found [llength $bif_files]"
}
set output_dir [file dirname [lindex $bif_files 0]]

if {![file exists [file join $hardware_dir system.hdf]]} {
    error "SDK hardware project is missing; run create_workspace.tcl first"
}

setws $workspace_dir
if {![file exists [file join $workspace_dir pqm_fsbl_bsp]]} {
    createbsp -name pqm_fsbl_bsp -hwproject pqm_hw -proc ps7_cortexa9_0 \
        -os standalone
}
setlib -bsp pqm_fsbl_bsp -lib xilffs -ver 4.0
regenbsp -bsp pqm_fsbl_bsp
projects -build -type bsp -name pqm_fsbl_bsp
if {![file exists [file join $workspace_dir pqm_fsbl]]} {
    createapp -name pqm_fsbl -hwproject pqm_hw -proc ps7_cortexa9_0 \
        -os standalone -lang C -app {Zynq FSBL} -bsp pqm_fsbl_bsp
}
projects -build -type app -name pqm_fsbl

set fsbl_file [file join $workspace_dir pqm_fsbl Debug pqm_fsbl.elf]
if {![file exists $fsbl_file]} {
    error "FSBL was not produced: $fsbl_file"
}
file mkdir $output_dir
file copy -force $fsbl_file [file join $output_dir zynq_fsbl.elf]
puts "Built PQM FSBL: $fsbl_file"
