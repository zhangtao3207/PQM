for {set i 0} {$i < 80} {incr i} {
    run 200 ns
    echo t=$i state=[examine sim:/ADC_tb/dut/state] rstcnt=[examine sim:/ADC_tb/dut/rst_cnt] rw=[examine sim:/ADC_tb/dut/reset_wait_cnt] conv=[examine sim:/ADC_tb/FPGA_CONVST] busy=[examine sim:/ADC_tb/dut/busy_sync]
}
quit -f
