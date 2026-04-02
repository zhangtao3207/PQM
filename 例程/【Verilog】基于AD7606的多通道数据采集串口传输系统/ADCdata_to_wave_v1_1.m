%====================================================================%
%设置ADC采集数据有效位宽
ADC_DATA_WIDTH = 16;
%ADC采集电压范围±VOL_RANGE (V)
VOL_RANGE = 5;
%采样率(Hz)
SAMPLE_RATE = 50000000;
%ADC采集电压分辨率 LSB
LSB = VOL_RANGE*2/(2^ADC_DATA_WIDTH);
%====================================================================%

%读取文件数据，转换成波形显示
src_data=textread('11.txt','%s');
src_data_hex=hex2dec(src_data)
DATA_NUM = length(src_data_hex);
voltage_code = 1:DATA_NUM/2;
voltage_code = voltage_code';
for i=1:1:DATA_NUM/2
  if src_data_hex(2*i-1)+src_data_hex(i*2)*256 > 2^(ADC_DATA_WIDTH-1)
    voltage_code(i) = src_data_hex(2*i-1)+src_data_hex(i*2)*256-2^ADC_DATA_WIDTH;
  else
    voltage_code(i) = src_data_hex(2*i-1)+src_data_hex(i*2)*256;
  end
end

%二进制ADC数据转换为电压值
voltage = voltage_code*LSB - LSB/2;
%ADC采样时间
sample_t = 1:DATA_NUM/2;
sample_t = sample_t';
for i=1:1:DATA_NUM/2
  sample_t(i) = 1000000/SAMPLE_RATE * i;
end

plot(sample_t,voltage);
axis([0 1000000/SAMPLE_RATE*DATA_NUM/2 -VOL_RANGE VOL_RANGE]) 
title('ADC采集电压显示')
xlabel('采样时间/(us)')
ylabel('电压/(V)')
grid on