set objs [list /ADC_DRIVER_TB/clk /ADC_DRIVER_TB/rst_n /ADC_DRIVER_TB/rddata]
run 100 ns
puts "T1=[current_time -s],[get_value -radix unsigned /ADC_DRIVER_TB/clk],[get_value -radix hex /ADC_DRIVER_TB/rddata]"
run 100 ns
puts "T2=[current_time -s],[get_value -radix unsigned /ADC_DRIVER_TB/clk],[get_value -radix hex /ADC_DRIVER_TB/rddata]"
quit
