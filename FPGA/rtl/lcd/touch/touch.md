# LCD Touch 模块说明

## 文件说明

本文件用于说明 `rtl/lcd/touch` 目录下触摸相关模块的职责划分和当前工程中的连接关系。
这一层只负责触摸控制器访问、坐标读取和手势事件生成。

## 模块划分

- `touch_top.v`
  触摸子系统顶层封装，对外输出统一的触摸数据和事件接口。
- `i2c_dri.v`
  通用 I2C 位级事务引擎，负责底层 SCL/SDA 时序。
- `touch_dri.v`
  触摸芯片协议层，负责复位、芯片识别、状态轮询与坐标读取。
- `touch_state.v`
  手势状态层，根据稳定坐标流生成点击、长按、拖动等事件。

## 当前数据流

```text
touch_top
    -> i2c_dri    : 完成 I2C 总线事务
    -> touch_dri  : 读取触摸控制器状态和坐标
    -> touch_state: 生成点击/长按/拖动等高层事件
```

## 对上层输出

- 原始坐标：`data = {x, y}`
- 触摸事件：
  - `touch_pressed`
  - `touch_unpressed`
  - `touch_click`
  - `touch_long_press`
  - `touch_drag`
- 手势附带信息：
  - 起点坐标
  - 终点坐标
  - 按压时间

## 维护约定

- `touch_top.v` 是对上层暴露的统一接口。
- 若只调整手势判定阈值，优先改 `touch_state.v`。
- 若更换触摸芯片协议，优先改 `touch_dri.v`。
