set objs [get_objects -r /ADC_DRIVER_TB/*]
puts "COUNT=[llength $objs]"
foreach obj [lrange $objs 0 40] { puts $obj }
quit
