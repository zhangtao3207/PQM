set w [get_waves /ADC_DRIVER_TB/clk]
puts "W=$w"
report_wave_props $w
quit
