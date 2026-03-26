proc csv_escape {value} {
    set text [string map {\" \"\"} $value]
    return "\"$text\""
}

proc dump_row {fp objects} {
    set fields [list [csv_escape [current_time -s]]]
    foreach obj $objects {
        if {[catch {get_value $obj} value]} {
            set value ""
        }
        lappend fields [csv_escape $value]
    }
    puts $fp [join $fields ","]
}

set csv_out [expr {[info exists ::env(CSV_OUT)] ? $::env(CSV_OUT) : "sim_all.csv"}]
set scope   [expr {[info exists ::env(CSV_SCOPE)] ? $::env(CSV_SCOPE) : "/ADC_DRIVER_TB"}]
set step    [expr {[info exists ::env(CSV_STEP)] ? $::env(CSV_STEP) : "10ns"}]

set objects [lsort [get_objects -r ${scope}/*]]
if {[llength $objects] == 0} {
    puts "ERROR: no HDL objects found under $scope"
    quit 1
}

set fp [open $csv_out "w"]

set header [list [csv_escape "time"]]
foreach obj $objects {
    lappend header [csv_escape $obj]
}
puts $fp [join $header ","]

restart
dump_row $fp $objects

set prev_time [current_time -s]
while {1} {
    run $step
    set now_time [current_time -s]
    if {$now_time eq $prev_time} {
        break
    }

    dump_row $fp $objects
    set prev_time $now_time
}

close $fp
puts "CSV export completed: $csv_out"
puts "Scope: $scope"
puts "Objects: [llength $objects]"
puts "Step: $step"
quit
