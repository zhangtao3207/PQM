open_wave_database {C:/Users/zhangtao/Desktop/PQM/FPGA/prj/PQM.sim/sim_1/behav/xsim/ADC_DRIVER_TB_behav.wdb}
set objs [get_objects -r /ADC_DRIVER_TB/*]
puts "NUM_OBJS=[llength $objs]"
foreach obj [lrange $objs 0 9] { puts "OBJ:$obj" }
puts "WAVES0=[get_waves]"
add_wave /ADC_DRIVER_TB/clk /ADC_DRIVER_TB/rst_n /ADC_DRIVER_TB/rddata
puts "WAVES1=[get_waves]"
report_wave_props [get_waves]
quit
