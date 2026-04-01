# LCD UI Notes

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
| Left panel | `x=0, y=64, w=480, h=392`, no outer border |
| Right panel | `x=500, y=64, w=276, h=392` |
| Divider | `x=486, y=64, w=4, h=392` |
| Freeze button | `x=572, y=6, w=102, h=32` |
| Auto button | `x=692, y=6, w=80, h=32` |

## Plot Area

| Item | Value |
| --- | --- |
| Graph box | `x=36, y=144, w=384, h=240` |
| Zero horizontal line | centered at `y=264` |
| Left vertical axis | `x=36`, highlighted bright line |
| Right vertical axis / time zero line | `x=419`, same highlighted bright line as left |
| Time window | `40 ms` |
| Signal cycles in window | `2 cycles @ 50 Hz` |
| Vertical grid pitch | `40 px` |
| Horizontal grid pitch | `96 px` |

## Left-Side Text

| Text | Position |
| --- | --- |
| `MODE: Single - TIime` | `x=32, y=6`, `16x32` |
| `Freeze` | `x=578, y=6`, `16x32` |
| `Auto` | `x=700, y=6`, `16x32` |
| `Time Domain Analysis` | `x=68, y=72`, `16x32` |
| `Voltage ( V)` | `x=40, y=118`, `10x20`, top-left of graph |
| `Current (A)` | `x=306, y=118`, `10x20`, top-right of graph |
| `Time(ms)` | `x=336, y=416`, `10x20`, bottom-right of graph |
| Voltage scale | `+5` to `-5`, `10x20`, `x=12`, step `24 px` |
| Current scale | `+0.3` to `-0.3`, `10x20`, `x=424`, step `40 px` |
| Time ticks | `-40 / -30 / -20 / -10 / 0`, `10x20`, `y=392` |

## Right-Side Text

| Row | Text |
| --- | --- |
| Header | `Parameterss` |
| Legend 1 | `U` |
| Legend 2 | `I` |
| 1 | `Sampling: 5 (KPS)` |
| 2 | `Voltage: [sign]XX.XX (V)` |
| 3 | `Current: 0.03 (A)` |
| 4 | `Phase Diff: 0.49 (rad)` |

## Color Map

| Name | RGB |
| --- | --- |
| Background | `0B1524` |
| Title bar | `173B63` |
| Left panel | `142235` |
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

- The plot now renders a voltage waveform in the graph area using the `39E46F` trace color.
- The waveform is displayed with an oscilloscope-style trigger method: rising zero-cross trigger, `40 ms` history window, and the trigger instant aligned to the right-side `t=0` axis.
- The current implementation draws the voltage trace only; the current axis and legend remain reserved for a future current-signal path.
- The right-side parameter panel keeps only the required header, U/I legend, and 4 parameter lines.
- Numeric tick labels are rendered for voltage, current, and time.

## Notes

- The horizontal zero line is centered to make positive and negative values easier to read.
- The right border of the graph is also the time-zero line and uses the same highlighted bright style as the left vertical axis.
- `Voltage ( V)`, `Current (A)`, `Time(ms)`, all plot tick labels, and the right-side parameter text use the `10x20` font ROM.
- Top title and button captions use the `16x32` font ROM.
- The left panel outer border is intentionally removed to free more space for the new axis scales.
- `lcd.html` in the same folder is a browser preview of the current Verilog layout.
- The waveform frame is frozen on each valid trigger event so the `50 Hz` signal appears visually stable instead of sweeping too fast.
- `font_rom_16x32.v` has dedicated lowercase `y/z` glyphs so `Time Domain Analysis` renders correctly on the FPGA LCD.
- The `Voltage` item in the right-side panel is now driven by the `ADC_TEMP` chain in `main.v`, using the sampled ADC result instead of a fixed string.

## Maintenance Prompt

- Prompt: after the Verilog LCD implementation is completed, convert the Verilog-equivalent display into `lcd.html` and update `lcd.md` at the same time.
