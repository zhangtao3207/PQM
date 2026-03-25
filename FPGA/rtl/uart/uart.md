# UART 模块说明

本目录包含 3 个 UART 相关模块：

- `uart.v`：顶层封装模块
- `uart_rx.v`：串口接收模块
- `uart_tx.v`：串口发送模块

默认协议为 `8N1`：

- 1 位起始位，低电平
- 8 位数据位，低位先发
- 1 位停止位，高电平
- 无校验位

## 1. 模块连接关系

```mermaid
flowchart LR
    RX_IN([uart_rxd])
    TX_IN([tx_en<br/>tx_data])
    RX_OUT([rx_data<br/>rx_done])
    TX_OUT([uart_txd<br/>tx_busy])

    subgraph TOP[uart.v]
        direction TB
        RX[uart_rx.v]
        TX[uart_tx.v]
    end

    RX_IN --> RX
    TX_IN --> TX
    RX --> RX_OUT
    TX --> TX_OUT
```

简短说明：

- `uart.v` 不做收发协议处理，只负责把 `uart_rx` 和 `uart_tx` 封装到一起。
- `uart_rx.v` 负责从 `uart_rxd` 上接收 1 字节数据，并在接收完成后输出 `rx_done` 脉冲。
- `uart_tx.v` 负责把上层给出的 1 字节数据按 UART 时序从 `uart_txd` 发出去，并在发送期间拉高 `tx_busy`。

## 2. uart.v

### 功能

`uart.v` 是顶层封装模块，用统一接口对外提供 UART 收发功能。

### 输入输出

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | 输入 | 1 | 系统时钟 |
| `rst_n` | 输入 | 1 | 低有效复位 |
| `uart_rxd` | 输入 | 1 | UART 串行接收输入 |
| `uart_txd` | 输出 | 1 | UART 串行发送输出 |
| `tx_en` | 输入 | 1 | 发送触发信号 |
| `tx_data` | 输入 | 8 | 要发送的 1 字节数据 |
| `tx_busy` | 输出 | 1 | 发送忙标志 |
| `rx_data` | 输出 | 8 | 接收到的 1 字节数据 |
| `rx_done` | 输出 | 1 | 接收完成脉冲 |

### 内部连接

- `uart_rxd -> uart_rx.v`
- `uart_rx.v` 输出 `uart_rx_data/uart_rx_done -> rx_data/rx_done`
- `tx_en/tx_data -> uart_tx.v`
- `uart_tx.v` 输出 `uart_txd/uart_tx_busy -> uart_txd/tx_busy`

### 流程图

```mermaid
flowchart TD
    A[输入 clk 
     rst_n 
     uart_rxd 
     tx_en 
     tx_data] --> B[实例化 uart_rx]
    A --> C[实例化 uart_tx]
    B --> D[输出 rx_data rx_done]
    C --> E[输出 uart_txd tx_busy]
```

## 3. uart_rx.v

### 功能

`uart_rx.v` 用于接收 UART 串口数据，完成以下动作：

- 对 `uart_rxd` 做三级寄存器同步
- 检测起始位下降沿
- 按波特率计数，在每一位的中点采样
- 接收 8 位数据
- 校验起始位和停止位
- 输出 `uart_rx_data` 和 `uart_rx_done`

### 输入输出

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | 输入 | 1 | 系统时钟 |
| `rst_n` | 输入 | 1 | 低有效复位 |
| `uart_rxd` | 输入 | 1 | UART 串行输入，空闲为高 |
| `uart_rx_data` | 输出 | 8 | 接收到的 1 字节数据 |
| `uart_rx_done` | 输出 | 1 | 接收完成脉冲 |

### 核心寄存器/信号

| 名称 | 作用 |
| --- | --- |
| `uart_rxd_d0/d1/d2` | 对异步串口输入做三级同步 |
| `start_edge` | 检测起始位下降沿 |
| `rx_flag` | 接收进行中标志 |
| `baud_cnt` | 波特率计数器 |
| `mid_tick` | 位中点采样时刻 |
| `rx_cnt` | 当前接收到第几位，`0` 表示起始位，`1~8` 表示数据位，`9` 表示停止位 |
| `rx_data_t` | 临时接收数据寄存器 |
| `frame_ok` | 帧有效标志，用于检查起始位和停止位 |

### 接收流程

```mermaid
flowchart TD
    A[空闲状态 uart_rxd为高] --> B[三级同步输入信号]
    B --> C{检测到起始位下降沿?}
    C -- 否 --> A
    C -- 是 --> D[置位 rx_flag 开始接收]
    D --> E[baud_cnt 按位时间计数]
    E --> F{到达位中点 mid_tick?}
    F -- 否 --> E
    F -- 是 --> G[按 rx_cnt 采样]
    G --> H{rx_cnt=0?}
    H -- 是 --> I[校验起始位应为0]
    H -- 否 --> J{rx_cnt=1~8?}
    J -- 是 --> K[依次保存8位数据到 rx_data_t]
    J -- 否 --> L[校验停止位应为1]
    I --> M{一帧结束?}
    K --> M
    L --> M
    M -- 否 --> E
    M -- 是 --> N{frame_ok有效?}
    N -- 是 --> O[输出 uart_rx_data 和 uart_rx_done]
    N -- 否 --> P[丢弃本帧]
    O --> A
    P --> A
```

### 简短说明

- 模块在 `start_edge` 出现后开始接收。
- 每一位只在中点采样一次，降低边沿附近误采样的概率。
- 只有起始位正确且停止位为高时，才输出 `uart_rx_done=1`。

## 4. uart_tx.v

### 功能

`uart_tx.v` 用于发送 UART 串口数据，完成以下动作：

- 对 `uart_tx_en` 做沿检测
- 在空闲时锁存待发送字节
- 按波特率逐位发送起始位、8 位数据位和停止位
- 发送期间输出 `uart_tx_busy`

### 输入输出

| 端口 | 方向 | 位宽 | 说明 |
| --- | --- | --- | --- |
| `clk` | 输入 | 1 | 系统时钟 |
| `rst_n` | 输入 | 1 | 低有效复位 |
| `uart_tx_en` | 输入 | 1 | 发送触发脉冲 |
| `uart_tx_data` | 输入 | 8 | 待发送的 1 字节数据 |
| `uart_txd` | 输出 | 1 | UART 串行输出，空闲为高 |
| `uart_tx_busy` | 输出 | 1 | 发送忙标志 |

### 核心寄存器/信号

| 名称 | 作用 |
| --- | --- |
| `uart_tx_en_d0` | 对发送使能打一拍，用于上升沿检测 |
| `tx_start` | 发送启动信号，仅在空闲时有效 |
| `baud_cnt` | 波特率计数器 |
| `baud_tick` | 一个比特发送时间结束标志 |
| `tx_cnt` | 当前发送到第几位，`0` 为起始位，`1~8` 为数据位，`9` 为停止位 |
| `tx_data_t` | 锁存的待发送字节 |

### 发送流程

```mermaid
flowchart TD
    A[空闲状态 uart_txd=1] --> B{检测到 uart_tx_en 上升沿且不忙?}
    B -- 否 --> A
    B -- 是 --> C[锁存 uart_tx_data 到 tx_data_t]
    C --> D[置位 uart_tx_busy]
    D --> E[baud_cnt 开始计数]
    E --> F[按 tx_cnt 输出对应位]
    F --> G{baud_tick 到达?}
    G -- 否 --> F
    G -- 是 --> H[tx_cnt加1]
    H --> I{发送完停止位?}
    I -- 否 --> E
    I -- 是 --> J[清除 uart_tx_busy 返回空闲]
    J --> A
```

### 位发送顺序

| `tx_cnt` | 发送内容 |
| --- | --- |
| `0` | 起始位 `0` |
| `1` | `tx_data_t[0]` |
| `2` | `tx_data_t[1]` |
| `3` | `tx_data_t[2]` |
| `4` | `tx_data_t[3]` |
| `5` | `tx_data_t[4]` |
| `6` | `tx_data_t[5]` |
| `7` | `tx_data_t[6]` |
| `8` | `tx_data_t[7]` |
| `9` | 停止位 `1` |

### 简短说明

- `uart_tx_en` 必须是触发脉冲，且发送时机要避开 `uart_tx_busy=1`。
- 模块只发送 1 字节；如果要连续发送多字节，需要上层状态机逐字节喂入。

## 5. 收发模块协同关系

```mermaid
flowchart LR
    A[上层逻辑] -->|发送数据| B[uart_tx.v]
    B -->|串行波形 uart_txd| C[外部设备]
    C -->|串行波形 uart_rxd| D[uart_rx.v]
    D -->|接收结果 rx_data rx_done| A
```

简短总结：

- `uart_tx.v` 解决“并行 8 位数据如何按 UART 时序发出去”。
- `uart_rx.v` 解决“UART 串行波形如何恢复成 8 位并行数据”。
- `uart.v` 解决“给上层一个统一的收发接口”。
