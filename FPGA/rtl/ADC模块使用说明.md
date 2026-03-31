# ADC 模块使用说明

## 1. 当前工程里真正生效的是哪一套 ADC 驱动

当前 `main.v` 实际实例化的不是 `FPGA/rtl/adc/AD7606_Drive.v`，而是下面这条链路：

`main.v` -> `ADC_SERIAL/AD7606_SPI_DRIVER.v` -> `ADC_SERIAL/ad7606_serial_ctrl.v`

也就是说，如果你要在当前工程里接入或复用 ADC，请以 `AD7606_SPI_DRIVER` 这套接口为准。

`FPGA/rtl/adc/AD7606_Drive.v` 更像是早期版本，只适合参考，不是当前顶层实际使用的模块。

## 2. 模块作用

这套驱动完成的是一次完整的 AD7606 串行采样流程：

1. 上电后给 ADC 一个复位脉冲
2. 等待外部 `start` 上升沿
3. 产生一次 `CONVST`
4. 等待 ADC 的 `BUSY` 先拉高、再拉低
5. 拉低 `CS#`，输出 `SCLK`
6. 串行读完 8 路、每路 16 bit，总计 128 bit
7. 把结果打包到 `data_frame`
8. 用 `data_valid` 给出 1 个时钟周期的有效脉冲

## 3. 对外接口怎么用

### 输入

- `clk`
  驱动工作时钟。当前工程用的是 50 MHz。

- `rst_n`
  低有效复位。拉低后模块进入复位态，重新给 ADC 输出复位脉冲。

- `start`
  启动一次采样的触发信号。
  这里看的是上升沿，不是电平持续有效。
  最安全的用法是只给 1 个 `clk` 周期的脉冲。

- `soft_reset`
  软件复位。
  给一个上升沿后，控制器会重新回到内部 `ST_RESET` 状态。

- `os_mode[2:0]`
  直接透传到 `OS2:OS0`。
  代码本身不做译码，只负责把这个 3bit 输出到引脚。

- `range_sel`
  直接透传到 `RANGE` 引脚。

- `ad_busy`
  ADC 的 `BUSY` 输入。

- `ad_frstdata`
  ADC 的 `FRSTDATA` 输入。
  当前版本会在读取第 1 通道第 1 bit 时检查它是否为高，用来确认串行数据起点已经和首通道对齐。
  如果这时 `FRSTDATA` 不为高，本次采样会判为异常，`timeout` 会置 1。

- `ad_sdata`
  ADC 串行数据输入，当前实现按单数据线顺序读 8 路数据。

### 输出

- `ad_reset`
  接 ADC 的 `RESET`，高有效。

- `ad_convst`
  接 ADC 的 `CONVST`。
  模块会先拉低一段时间，再拉高，真正启动转换的是释放回高后的边沿。

- `ad_cs_n`
  接 ADC 的 `CS#`，低有效。

- `ad_sclk`
  接 ADC 的串行时钟。

- `ad_os0/ad_os1/ad_os2`
  过采样模式输出。

- `ad_range`
  量程选择输出。

- `ch1_data` ~ `ch8_data`
  8 路 16 bit 采样结果。

- `data_frame[127:0]`
  8 路打包结果，排列方式是：
  `data_frame[15:0]   = ch1`
  `data_frame[31:16]  = ch2`
  `data_frame[47:32]  = ch3`
  `data_frame[63:48]  = ch4`
  `data_frame[79:64]  = ch5`
  `data_frame[95:80]  = ch6`
  `data_frame[111:96] = ch7`
  `data_frame[127:112]= ch8`

- `data_valid`
  一次采样完成后的有效脉冲，宽度为 1 个 `clk` 周期。
  取数建议就在这个脉冲到来时锁存。

- `sample_active`
  为 1 表示模块正在复位、转换或读数。
  为 0 表示模块空闲，可以接受下一次 `start`。

- `timeout`
  超时标志。
  如果 `BUSY` 没按预期拉高，或者拉高后一直不拉低，会置 1。
  下一次新的 `start` 或复位会清掉它。

## 4. 最小使用步骤

### 4.1 硬件连接

至少要把下面这些信号接好：

- `ad_reset` -> ADC `RESET`
- `ad_convst` -> ADC `CONVST`
- `ad_cs_n` -> ADC `CS#`
- `ad_sclk` -> ADC `RD/SCLK`
- `ad_busy` <- ADC `BUSY`
- `ad_frstdata` <- ADC `FRSTDATA`
- `ad_sdata` <- ADC 串行数据输出

如果你的板子把 `OS[2:0]` 和 `RANGE` 也引到了 FPGA，再接：

- `ad_os0/ad_os1/ad_os2` -> ADC `OS0/OS1/OS2`
- `ad_range` -> ADC `RANGE`

如果板子上这些脚已经硬件绑死，那这几个输出可以不接。

### 4.2 上电后等待空闲

不要在模块还没退出内部复位时就发 `start`。

最简单的判断方式是：

- `sample_active == 0`

只有空闲时再发启动脉冲。

### 4.3 发启动脉冲

给 `start` 一个单周期脉冲：

```verilog
if (!sample_active) begin
    start <= 1'b1;
end else begin
    start <= 1'b0;
end
```

更稳妥的写法是只打一拍，然后等待这次采样结束。

### 4.4 等待结果有效

当 `data_valid == 1` 时，表示本次 8 路数据已经全部装好。

这时读取：

- `ch1_data` ~ `ch8_data`
  或
- `data_frame`

都可以。

### 4.5 超时处理

如果发现 `timeout == 1`，说明本次 ADC 握手异常。

可选处理方式：

- 重新发起一次 `start`
- 给 `soft_reset` 一个脉冲
- 检查 `BUSY`、`SCLK`、`CS#` 和数据线连接

## 5. 一个可直接照抄的单次采样例子

```verilog
reg adc_start;
wire [15:0] ch1_data;
wire [15:0] ch2_data;
wire [127:0] data_frame;
wire data_valid;
wire sample_active;
wire timeout;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        adc_start <= 1'b0;
    end else begin
        adc_start <= 1'b0;
        if (!sample_active) begin
            adc_start <= 1'b1; // 只打一拍
        end
    end
end

AD7606_SPI_DRIVER #(
    .RESET_HIGH_CYCLES(200),
    .CONVST_LOW_CYCLES(10),
    .SCLK_LOW_CYCLES(4),
    .SCLK_HIGH_CYCLES(4),
    .BUSY_TIMEOUT_CYCLES(50000)
) u_adc (
    .clk(clk),
    .rst_n(rst_n),
    .start(adc_start),
    .soft_reset(1'b0),
    .os_mode(3'd0),
    .range_sel(1'b0),
    .ad_busy(ad_busy),
    .ad_frstdata(ad_frstdata),
    .ad_sdata(ad_sdata),
    .ad_reset(ad_reset),
    .ad_convst(ad_convst),
    .ad_cs_n(ad_cs_n),
    .ad_sclk(ad_sclk),
    .ad_os0(),
    .ad_os1(),
    .ad_os2(),
    .ad_range(),
    .ch1_data(ch1_data),
    .ch2_data(ch2_data),
    .ch3_data(),
    .ch4_data(),
    .ch5_data(),
    .ch6_data(),
    .ch7_data(),
    .ch8_data(),
    .data_frame(data_frame),
    .data_valid(data_valid),
    .sample_active(sample_active),
    .timeout(timeout)
);

always @(posedge clk) begin
    if (data_valid) begin
        // 在这里锁存 ch1_data/ch2_data 或 data_frame
    end
end
```

## 6. 当前 `main.v` 里是怎么用的

当前工程顶层已经给了一个连续采样示例，逻辑是：

1. 系统复位后先等待一段启动延时
2. 当 `sample_active == 0` 时自动发一个 `start` 脉冲
3. 模块开始一次完整采样
4. 再次回到空闲后继续下一次

也就是当前 `main.v` 默认是“空闲就继续采”的工作方式，不是手动单次采样。

## 7. 当前项目里几个很重要的实际情况

### 7.1 当前顶层只真正使用了两路数据

从 `main.v` 看，当前工程只接了：

- `ch1_data -> adc_v1_data`
- `ch2_data -> adc_v2_data`

`ch3_data` 到 `ch8_data` 都没有接到后续逻辑。

### 7.2 当前顶层没有把 `OS` 和 `RANGE` 真正引到板级端口

虽然 `AD7606_SPI_DRIVER` 有：

- `ad_os0`
- `ad_os1`
- `ad_os2`
- `ad_range`

但在 `main.v` 里这几个口目前是空着的。

这意味着：

- 你在代码里改 `os_mode`
- 你在代码里改 `range_sel`

如果板子上没有把这些信号接到 FPGA 引脚，那么硬件行为不会因此改变。

### 7.3 当前读取的是单串行数据口

现有控制器只有一个 `ad_sdata` 输入，没有同时读 `DOUTA/DOUTB` 两路。

所以当前实现是：

- 单线串行
- 依次读完 8 个通道
- 每通道 16 bit
- 一共 128 个串行位

## 8. 当前板上的通道含义

结合仓库里的硬件说明，当前板上主要使用：

- `CH1 / V1`：电流采样通道
- `CH2 / V2`：电压采样通道

其余 `CH3 ~ CH8` 目前没有在主流程里使用。

## 9. 什么时候不要直接照抄当前实现

下面几种情况需要改驱动，而不是只改参数：

- 你想同时读 `DOUTA` 和 `DOUTB`
- 你想用并行模式
- 你想让 `OS` / `RANGE` 真正可配置，但现在板子没把这些脚接出来
- 你要改成固定采样率触发，而不是“空闲就继续采”

## 10. 一句话总结

当前 ADC 模块的标准用法就是：

`空闲时给 start 一个上升沿 -> 等 BUSY 完成 -> 模块自动串行读完 8 路 -> 在 data_valid 那一拍取 ch1_data~ch8_data 或 data_frame`
