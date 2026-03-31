catch {get_value -help} msg1
puts "GET_VALUE_HELP_START"
puts $msg1
puts "GET_VALUE_HELP_END"
catch {report_values -help} msg2
puts "REPORT_VALUES_HELP_START"
puts $msg2
puts "REPORT_VALUES_HELP_END"
quit
