# LCD Display 模块说明

## 文件说明

本文件用于说明 `rtl/lcd/display` 目录下各显示模块的职责、连接关系和当前工程中的使用方式。
这一层只负责 LCD 页面渲染、字库、像素时钟与 LCD 时序，不负责 ADC 采样和波形分析算法本身。

## 模块划分

- `lcd_rgb_char.v`
  目录顶层封装，负责把面板 ID 识别、像素时钟选择、页面渲染和 LCD 时序串接起来。
- `rd_id.v`
  上电后从 LCD 复用总线读取面板 ID。
- `clk_div.v`
  根据 LCD ID 选择匹配的像素时钟。
- `lcd_display.v`
  页面总合成模块，负责调用背景层、文字层、字库 ROM、波形 RAM 和 DataProcessor 输出。
- `lcd_display_bg.v`
  页面静态背景层，绘制标题栏、按钮、参数区底板、坐标系边框和网格。
- `lcd_display_text.v`
  页面文字层，统一管理固定文案、坐标刻度和动态参数字符串。
- `lcd_driver.v`
  生成 LCD 扫描时序、像素坐标、DE 信号和 RGB 输出。
- `binary2bcd.v`
  将二进制数转换成 BCD，供显示链逐位取值。
- `font_rom_16x32.v`
  大字号 16x32 字模原始表。
- `font_rom_10x20.v`
  小字号 10x20 字模原始表。

## 当前数据流

```text
DataProcessor 输出数值/波形
    -> lcd_display.v
    -> lcd_display_bg.v / lcd_display_text.v / 字体 ROM / 波形 RAM
    -> lcd_driver.v
    -> LCD 面板接口
```

## 维护约定

- 页面布局以 `rtl/lcd/lcd.html` 为预览参考。
- RTL 修改后，应同步检查 `rtl/lcd/lcd.md` 与 `rtl/lcd/lcd.html`。
- 显示目录只保留渲染和时序相关逻辑；波形分析与数值算法放在 `rtl/DataProcessor`。
