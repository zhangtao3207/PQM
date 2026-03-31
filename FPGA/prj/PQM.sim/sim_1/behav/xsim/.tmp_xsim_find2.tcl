create_wave_config mycfg
add_wave /ADC_DRIVER_TB/clk
run 100 ns
set wave_clk [lindex [get_waves *clk] 0]
puts "WAVE_CLK=$wave_clk"
set hit [find_next_wave_value -wave $wave_clk -time 0ns 1]
puts "HIT=$hit"
quit
