create_wave_config mycfg
add_wave /ADC_DRIVER_TB/clk
add_wave /ADC_DRIVER_TB/rddata
set waves [get_waves *]
puts "WAVES=$waves"
report_wave_props $waves
quit
