# LCD 文字区刷新链路

本文只描述 LCD 文字区刷新关系，不涉及波形绘制链路。

## 刷新主链路

LCD 当前帧刷新完毕，`frame_done_toggle` 翻转，等价于本轮文字刷新触发。

-> `text_display_preprocess` 检测到 LCD 帧完成事件。

-> 等待约 20ms 文字刷新间隔。

-> 启动文字区参数总调度。

-> 启动 `parameters_initiator` 原始测量调度阶段。

-> `parameters_initiator` 对 `RawDataCal` 下 p2p、phase、frequency 原始测量模块发出启动脉冲。

-> 等待 p2p、phase、frequency 原始测量模块 `done`，并检查对应 `valid`。

-> p2p raw 有效后启动 `ui_rms_measure`，得到 U/I RMS raw。

-> RMS raw 与 phase raw 有效后启动 `power_metrics_calc`，得到 P/Q/S/PF raw。

-> 将同一批次获得的所有待测参数原始值锁存，统一为 `32位补码 raw`。

-> 原始数据齐备后发送到 `x100_normalizer`。

-> `x100_normalizer` 对各个 raw 参数进行 `x100` 定点换算，结果仍为 `32位补码值`。

-> `x100_normalizer` 换算完成后发送到 `data_separator`。

-> `data_separator` 将 `x100` 后的 32 位补码值拆分为符号位、百位、十位、个位、十分位、百分位。

-> `data_separator` 拆位完成后返回 `text_display_preprocess`。

-> `text_display_preprocess` 将所有文字区参数、数位和 valid 标志打包成完整 `text_packet`。

-> 翻转 `text_result_commit_toggle`，提交给 `text_packet_double_buffer`。

-> `text_packet_double_buffer` 在 `wave_clk` 域锁存完整数据包到后备 bank，并通过 toggle 跨时钟域通知 LCD 域。

-> LCD 域检测到新 packet pending 后，不立即打断当前显示，而是在下一次 LCD 帧边界切换 front bank。

-> 切换完成后翻转 `lcd_swap_ack_toggle` 返回应答，允许下一包写入。

-> LCD 文字渲染逻辑从 front packet 中取各参数数位，在文字区对应位置重新加载显示。

-> 当前文字帧显示完毕后，进入下一轮刷新循环。

## 模块职责

`lcd_driver`: 产生 LCD 扫描时序，并在完整帧结束时翻转 `frame_done_toggle`。

`lcd_display`: 负责文字包拼接、双缓冲实例化、LCD 域 front packet 锁存，以及文字层像素渲染入口。

`text_display_preprocess`: 负责文字刷新总调度，只按 `parameters_done -> x100_done -> separator_done -> commit` 顺序推进，不直接控制 RawDataCal 子模块。

`parameters_initiator`: 负责原始测量调度，统一启动电压峰峰值、电流峰峰值、相位差和频率测量，再派生 RMS raw 和功率 raw，并锁存同一批次的 raw/valid 输出。

`x100_normalizer`: 负责把 32 位补码 raw 参数统一换算为 x100 定点显示值，输出仍为 32 位补码。

`data_separator`: 负责把 x100 后的补码值拆成文字区显示所需的符号位和十进制数位。

`text_packet_double_buffer`: 负责 `wave_clk` 到 `lcd_pclk` 的文字包跨时钟域双缓冲，只同步 toggle/ack 控制位，宽数据包在 ack 返回前保持稳定。

`lcd_display_text`: 负责根据 LCD 域 front packet 中的数位和 valid 标志，在文字区对应位置生成字符选择和颜色信息。

## 约束

`text_display_preprocess` 只在空闲态响应新的 LCD 帧完成事件，避免上一轮文字包尚未提交完毕时重复启动。

`parameters_initiator` 必须等待 p2p、phase、frequency、RMS 和功率 raw 阶段结束后才返回 `done`，每个参数是否参与显示由对应 `valid` 决定。

`x100_normalizer` 只能在同一批 raw 结果锁存完成后启动，`data_separator` 只能在 `x100_done` 后启动。

`text_packet_double_buffer` 在上一包收到 `lcd_swap_ack_toggle` 前不覆盖 pending bank，避免 LCD 域读取半包数据。

LCD 域只在帧边界切换 front packet，不能在文字扫描中途切换，防止文字区半新半旧。
