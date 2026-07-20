# Vivado 2018.3 can attempt to remove its realtime/tmp directory after the
# directory has already disappeared on managed Windows filesystems. Treat that
# one idempotent cleanup as success while preserving every other file error.
if {[llength [info commands pqm_file_builtin]] == 0} {
    rename file pqm_file_builtin
    proc file {subcommand args} {
        set command [linsert $args 0 pqm_file_builtin $subcommand]
        if {$subcommand ne "delete"} {
            return [uplevel 1 $command]
        }

        set status [catch {uplevel 1 $command} result options]
        if {$status == 0} {
            return $result
        }

        set target_text [join $args " "]
        if {[string match "*realtime/tmp*" $target_text] &&
            [string match "*no such file or directory*" $result]} {
            return ""
        }
        return -options $options $result
    }
}
