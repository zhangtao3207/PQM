# 从 XSA 生成 Vitis 工作区、平台、BSP 与应用，把 app/ 下的源码同步进应用后编译。
#
# 运行：powershell -ExecutionPolicy Bypass -File scripts\build_app.ps1
#
# 生成物全部落在 build/ 下（已 gitignore），仓库里只保留源码。

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set xsa_file   [file join $repo_dir hw system_wrapper.xsa]
set app_src    [file join $repo_dir app]
set ws         [file join $repo_dir build vitis_ws]
set log_file   [file join $repo_dir export build_app.log]

set hw_name    pqm2_hw
set bsp_name   pqm2_bsp
set app_name   pqm2_app
set proc       ps7_cortexa9_0

file mkdir [file dirname $log_file]
set ::fh [open $log_file w]
fconfigure $::fh -encoding utf-8 -translation lf

proc plog {msg} {
    puts $msg
    catch {
        puts $::fh $msg
        flush $::fh
    }
}

proc copy_tree {src dst} {
    file mkdir $dst
    foreach entry [glob -nocomplain -directory $src *] {
        set target [file join $dst [file tail $entry]]
        if {[file isdirectory $entry]} {
            copy_tree $entry $target
        } else {
            file copy -force $entry $target
        }
    }
}

foreach required [list $xsa_file $app_src] {
    if {![file exists $required]} {
        plog "ERROR: missing $required"
        close $::fh
        return
    }
}

plog "=== workspace $ws ==="
file delete -force $ws
file mkdir $ws
setws $ws

plog "=== platform from XSA ==="
if {[catch {createhw -name $hw_name -hwspec $xsa_file} e]} {
    plog "ERROR createhw: $e"
} else {
    plog "platform created"
}
platform active $hw_name

plog "=== BSP (standalone) ==="
if {[catch {createbsp -name $bsp_name -hwproject $hw_name -proc $proc -os standalone} e]} {
    plog "ERROR createbsp: $e"
} else {
    plog "bsp created"
}

plog "=== application ==="
if {[catch {
    createapp -name $app_name -hwproject $hw_name -proc $proc \
        -os standalone -lang C -app {Empty Application(C)} -bsp $bsp_name
} e]} {
    plog "ERROR createapp: $e"
} else {
    plog "app created"
}

set app_dir [file join $ws $app_name]
if {![file exists $app_dir]} {
    plog "ERROR: app dir missing: $app_dir"
    close $::fh
    return
}

plog "=== syncing sources into the app ==="
copy_tree $app_src [file join $app_dir src]
plog "src file count: [llength [glob -nocomplain -directory [file join $app_dir src] *]]"

plog "=== 生成 makefile（app build）==="
if {[catch {app build -name $app_name} e]} {
    plog "ERROR app build: $e"
} else {
    plog "app build finished"
}

# 两个坑，缺一个都会失败：
#   1. app build 只重新生成 makefile，并不编译。真正的编译要直接调 Vitis 自带的 make。
#   2. 生成的 subdir.mk 里只带了 BSP 的 include 路径，应用自己的头文件目录不会被写进去。
#      这里用 GCC 认的 CPATH 把 app/src 下所有目录补进搜索路径；同时把 Vitis 的
#      gnuwin/bin 加进 PATH，因为链接后的 size 步骤要调用 tee。
proc find_vitis_make {} {
    set candidates [list]
    if {[info exists ::env(XILINX_VITIS)]} {
        lappend candidates [file join $::env(XILINX_VITIS) gnuwin bin make.exe]
    }
    lappend candidates {D:/zt/Xilinx/Vitis/2022.2/gnuwin/bin/make.exe}
    lappend candidates {D:/Xilinx/Vitis/2022.2/gnuwin/bin/make.exe}
    lappend candidates {C:/Xilinx/Vitis/2022.2/gnuwin/bin/make.exe}
    foreach candidate $candidates {
        if {[file exists $candidate]} { return $candidate }
    }
    return ""
}

proc collect_dirs {dir} {
    set result [list $dir]
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            foreach sub [collect_dirs $entry] { lappend result $sub }
        }
    }
    return $result
}

set make_exe [find_vitis_make]
if {$make_exe eq ""} {
    plog "ERROR: Vitis make.exe 未找到"
} else {
    set vitis_dir     [file normalize [file join [file dirname $make_exe] .. ..]]
    set gnuwin_bin    [file join $vitis_dir gnuwin bin]
    set toolchain_bin [file join $vitis_dir gnu aarch32 nt gcc-arm-none-eabi bin]

    set include_dirs [collect_dirs [file normalize [file join $app_dir src]]]
    set ::env(CPATH) [join $include_dirs ";"]
    set ::env(PATH)  "$toolchain_bin;$gnuwin_bin;$::env(PATH)"
    plog "include 目录: [llength $include_dirs] 个（经 CPATH 传给 gcc）"

    set make_log [file join $repo_dir export make_app.log]
    plog "=== 编译（$make_exe main-build）==="
    set old_wd [pwd]
    cd [file join $app_dir Debug]
    set make_failed [catch {exec $make_exe --no-print-directory main-build 2>@1} out]
    cd $old_wd
    set fh2 [open $make_log w]
    fconfigure $fh2 -encoding utf-8 -translation lf
    puts $fh2 $out
    close $fh2
    if {$make_failed} {
        plog "ERROR make：完整输出见 $make_log"
        foreach line [lrange [split $out "\n"] end-30 end] { plog "  $line" }
    } else {
        plog "编译完成，完整输出见 $make_log"
    }
}

set elfs [glob -nocomplain [file join $app_dir Debug *.elf] [file join $app_dir Release *.elf]]
plog "ELF candidates: $elfs"
foreach elf $elfs {
    plog "ELF $elf size=[file size $elf]"
}
plog "=== done ==="
close $::fh
