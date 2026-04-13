# LCD UI Notes

> 中文说明：
> 本文件记录当前 LCD 页面布局、字体、颜色、坐标区和右侧参数区设计约束，
> 用于同步 `lcd.html` 与 `lcd_display.v` 的界面定义。

This file documents the current LCD screen implemented in
`FPGA/rtl/lcd/display/lcd_display.v`.

## Scope

- Screen size target: `800 x 480`
- Current implementation owner: `lcd_display.v`
- Purpose: fixed time-domain waveform screen for FPGA LCD output
- Language on screen: English only
- Top title / button font: `16x32`
- Plot title font: `16x32`
- Axis / scale / right-panel font: `10x20`

## Main Layout

| Item | Value |
| --- | --- |
| Title bar | `x=0, y=0, w=800, h=44` |
| Left panel | `x=0, y=64, w=480, h=392`, no outer border and no background plate |
| Right panel | `x=500, y=64, w=276, h=392` |
| Divider | `x=486, y=64, w=4, h=392` |
| Mode button | `x=572, y=6, w=87, h=32` |
| Freeze button | `x=672, y=6, w=110, h=32` |

## Plot Area

| Item | Value |
| --- | --- |
| Graph box | `x=36, y=144, w=384, h=240` |
| Zero horizontal line | centered at `y=264` |
| Left vertical axis | `x=36`, highlighted bright line |
| Right vertical axis / time zero line | `x=419`, same highlighted bright line as left |
| Time window | `60 ms` |
| Signal cycles in window | `3 cycles @ 50 Hz` |
| Voltage-aligned horizontal pitch | `40 px` |
| Horizontal grid pitch | `96 px` |

## Left-Side Text

| Text | Position |
| --- | --- |
| `MODE: Single - Time` | `x=32, y=6`, `16x32` |
| `MODE` | `x=583, y=6`, `16x32` |
| `Freeze` | `x=680, y=6`, `16x32` |
| `Time Domain Analysis` | `x=68, y=72`, `16x32` |
| `Voltage ( V)` | `x=40, y=118`, `10x20`, top-left of graph |
| `Current (A)` | `x=306, y=118`, `10x20`, top-right of graph |
| `Time(ms)` | `x=336, y=416`, `10x20`, bottom-right of graph |
| Voltage scale | `+12 / +8 / +4 / 0 / -4 / -8 / -12`, `10x20`, `x=2`, step `40 px` |
| Current scale | `+0.3` to `-0.3`, `10x20`, `x=424`, step `40 px` |
| Time ticks | `-60 / -45 / -30 / -15 / 0`, `10x20`, `y=392` |
| `Upp: XX.XX (V)` | `x=68, y=425`, `10x20`, bottom-left |
| `Ipp: X.XX (A)` | `x=68, y=449`, `10x20`, bottom-left |

## Right-Side Text

| Row | Text |
| --- | --- |
| Header | `Parameters` |
| 1 | `Frequency: XXX.XX (Hz)` |
| 2 | `U_rms: XX.XX (V)` |
| 3 | `I_rms: X.XX (A)` |
| 4 | `Phase Diff: sXXX.XX (deg)` |

## Color Map

| Name | RGB |
| --- | --- |
| Background | `0B1524` |
| Title bar | `173B63` |
| Right panel | `101A28` |
| Panel border | `4F6D8F` |
| Graph background | `020406` |
| Grid | `243645` |
| Main horizontal axis | `8EA7BF` |
| Left/Right vertical axes | `EAF3FF` |
| Right zero axis | same as `Left/Right vertical axes` |
| Main text | `F2F6FA` |
| Secondary text | `C6D3E2` |
| Dim text | `95A9BE` |
| Button | `49617E` |
| Button border | `DEE9F5` |
| Voltage waveform | `39E46F` |
| Current waveform | `FFD84E` |
| Accent line | `58B6FF` |

## Waveform Model

- The plot now renders both voltage and current waveforms in the graph area using `39E46F` and `FFD84E`.
- The waveform is displayed with an oscilloscope-style trigger method: rising zero-cross trigger, `60 ms` history window, and the trigger instant aligned to the right-side `t=0` axis.
- `CH1` from the parallel ADC is used as the voltage path and `CH2` is used as the current path.
- The current waveform is captured with the same voltage-trigger snapshot so the plot shows the relative phase directly.
- The phase item shows the signed phase of voltage relative to current, in degrees. Positive means voltage leads current.
- The right-side parameter panel keeps only the required header and 4 parameter lines.
- Numeric tick labels are rendered for voltage, current, and time.
- The horizontal reference lines in the graph are aligned to the left voltage axis labels `+12 / +8 / +4 / 0 / -4 / -8 / -12`.
- `Upp` and `Ipp` are shown under the left plot area instead of occupying right-panel rows.

## Notes

- The horizontal zero line is centered to make positive and negative values easier to read.
- The right border of the graph is also the time-zero line and uses the same highlighted bright style as the left vertical axis.
- `Voltage ( V)`, `Current (A)`, `Time(ms)`, all plot tick labels, and the right-side parameter text use the `10x20` font ROM.
- Top title and button captions use the `16x32` font ROM.
- The left panel outer border is intentionally removed to free more space for the new axis scales.
- `lcd.html` in the same folder is a browser preview of the current Verilog layout.
- The waveform frame is frozen on each valid trigger event so the `50 Hz` signal appears visually stable instead of sweeping too fast.
- `font_rom_16x32.v` has dedicated lowercase `y/z` glyphs so `Time Domain Analysis` renders correctly on the FPGA LCD.
- The right-side `U_rms` item is driven by the active parallel-ADC `CH1` path, and `I_rms` is driven by `CH2`.
- The right-side `Frequency` item is derived from the voltage rising zero-cross period.
- `Upp` and `Ipp` are derived from the peak-to-peak span observed in the same raw sample stream over the current slow refresh window.
- The RMS display now uses a `x100` full-scale mapping: `10.00V` for the voltage path and `0.30A` for the current path.
- The RMS path uses equal-interval discrete RMS evaluation and then applies a 64-result moving average before display.
- The right-side RMS text area is throttled to refresh once every `500 ms` at the current `wave_clk=50 MHz` assumption.
- The phase-difference text is also throttled to refresh once every `500 ms` and is shown as a signed degree value.

## Maintenance Prompt

- Prompt: after the Verilog LCD implementation is completed, convert the Verilog-equivalent display into `lcd.html` and update `lcd.md` at the same time.
