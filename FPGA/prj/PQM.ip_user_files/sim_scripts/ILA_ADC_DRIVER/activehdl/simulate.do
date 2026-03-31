onbreak {quit -force}
onerror {quit -force}

asim -t 1ps +access +r +m+ILA_ADC_DRIVER -L xil_defaultlib -L xpm -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.ILA_ADC_DRIVER xil_defaultlib.glbl

do {wave.do}

view wave
view structure

do {ILA_ADC_DRIVER.udo}

run -all

endsim

quit -force
