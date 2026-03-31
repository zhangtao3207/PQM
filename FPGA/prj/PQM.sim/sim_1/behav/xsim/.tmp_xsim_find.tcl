add_wave /ADC_DRIVER_TB/clk /ADC_DRIVER_TB/rst_n /ADC_DRIVER_TB/rddata
run 500 ns
puts "TIME0=[current_time -s]"
set hit [find_next_wave_value -wave /ADC_DRIVER_TB/clk -time 0ns 0]
puts "HIT=$hit"
puts "TIME1=[current_time -s]"
puts "CLKVAL=[get_value /ADC_DRIVER_TB/clk]"
quit
