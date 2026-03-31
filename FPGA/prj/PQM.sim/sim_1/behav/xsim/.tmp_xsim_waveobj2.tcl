create_wave_config mycfg
set w [get_waves -of [current_wave_config] /ADC_DRIVER_TB/clk]
puts "W=$w"
report_wave_props $w
quit
