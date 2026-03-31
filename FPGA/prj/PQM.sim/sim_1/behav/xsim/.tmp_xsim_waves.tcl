add_wave /ADC_DRIVER_TB/clk /ADC_DRIVER_TB/rst_n /ADC_DRIVER_TB/rddata
puts "WAVES=[get_waves]"
puts "WAVECLK=[lindex [get_waves /ADC_DRIVER_TB/clk] 0]"
quit
