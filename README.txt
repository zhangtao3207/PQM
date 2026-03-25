基于FPGA的电能质量监测仪硬件系统设计与实现
Power Quality Monitor based on FPGA - ZYNQ 7020

ARM: 单片机部分
型号: STM32F1（暂定，未使用）
后续使用，现在暂不考虑


FPGA: 信号处理部分
型号: ZYNQ 7020
监测电能质量(单相220V 50Hz家庭用电)，包括
        电压
        电流
        频率
        有功功率
        功率因数
        电能
        电压 THD
        电流 THD
        各次谐波
        过压/欠压
        暂降/暂升/中断
        事件时间记录
        无功功率
        视在功率
        闪变
        瞬态尖峰
        波形录波



HARDWARE: 硬件部分
ADC模块
FPGA模块
STM模块
