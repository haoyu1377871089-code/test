# NPC + ysyxSoC 架构文档

本文档描述 NPC 处理器和 ysyxSoC 的详细架构，便于学习理解整个系统设计。

## 目录

1. [系统整体架构](#1-系统整体架构)
2. [NPC 处理器内部架构](#2-npc-处理器内部架构)
3. [模块详细说明](#3-模块详细说明)
4. [ysyxSoC 架构](#4-ysyxsoc-架构)
5. [AXI 协议栈](#5-axi-协议栈)
6. [关键文件列表](#6-关键文件列表)

---

## 1. 系统整体架构

NPC 处理器通过 AXI4 总线接口接入 ysyxSoC，访问各种存储器和外设。

```mermaid
graph TB
    subgraph NPC_CPU ["NPC 处理器核"]
        EXU["EXU<br/>执行单元"]
        ICache["ICache<br/>指令缓存<br/>4KB 2-way"]
        IFU_AXI["IFU_AXI<br/>取指接口"]
        LSU_AXI["LSU_AXI<br/>访存接口"]
        Arbiter["AXI4-Lite<br/>Arbiter"]
        Bridge["AXI4-Lite<br/>to AXI4<br/>Bridge"]
    end
    
    subgraph ysyxSoC ["ysyxSoC"]
        Xbar["AXI4 Xbar<br/>主交叉开关"]
        Xbar2["AXI4 Xbar2<br/>二级交叉开关"]
        AXI2APB["AXI4ToAPB<br/>桥接器"]
        APBFanout["APB Fanout<br/>外设总线"]
        
        subgraph Memory ["存储器"]
            MROM["MROM<br/>0x20000000"]
            SRAM["SRAM<br/>0x0f000000"]
            PSRAM["PSRAM<br/>0x80000000"]
            SDRAM["SDRAM<br/>0xa0000000"]
        end
        
        subgraph Peripherals ["外设"]
            UART["UART<br/>0x10000000"]
            SPI["SPI<br/>0x10001000"]
            GPIO["GPIO<br/>0x10002000"]
            VGA["VGA<br/>0x21000000"]
            Flash["Flash XIP<br/>0x30000000"]
        end
    end
    
    EXU -->|指令请求| ICache
    ICache -->|miss| IFU_AXI
    EXU -->|数据请求| LSU_AXI
    IFU_AXI -->|M0| Arbiter
    LSU_AXI -->|M1| Arbiter
    Arbiter --> Bridge
    Bridge -->|AXI4| Xbar
    Xbar --> Xbar2
    Xbar2 --> AXI2APB
    Xbar2 --> MROM
    Xbar2 --> SRAM
    AXI2APB --> APBFanout
    APBFanout --> UART
    APBFanout --> SPI
    APBFanout --> GPIO
    APBFanout --> VGA
    APBFanout --> PSRAM
    APBFanout --> Flash
    APBFanout --> SDRAM
```

### 系统特点

- **处理器架构**: RISC-V RV32E，单发射顺序执行
- **指令缓存**: 4KB 2-way 组相联，98%+ 命中率
- **总线协议**: 内部 AXI4-Lite，外部 AXI4
- **外设访问**: 通过 APB 总线桥接

---

## 2. NPC 处理器内部架构

### 2.1 顶层模块 `ysyx_00000000.v`

```mermaid
graph LR
    subgraph Control ["控制逻辑"]
        PC["PC 寄存器"]
        FSM["取指状态机"]
    end
    
    subgraph Datapath ["数据通路"]
        EXU["EXU<br/>执行单元"]
        RegFile["寄存器文件<br/>x0-x15"]
    end
    
    subgraph IFU_Path ["取指路径"]
        ICache["ICache<br/>ifdef ENABLE_ICACHE"]
        IFU_AXI["IFU_AXI"]
    end
    
    subgraph LSU_Path ["访存路径"]
        LSU_AXI["LSU_AXI"]
    end
    
    subgraph Bus_Interface ["总线接口"]
        Arbiter["AXI4-Lite<br/>Arbiter"]
        Bridge["AXI4-Lite<br/>to AXI4"]
    end
    
    PC -->|ifu_addr| ICache
    FSM -->|ifu_req| ICache
    ICache -->|hit| EXU
    ICache -->|miss| IFU_AXI
    IFU_AXI --> Arbiter
    
    EXU -->|lsu_req| LSU_AXI
    LSU_AXI --> Arbiter
    EXU -->|next_pc| PC
    EXU -->|branch_taken| FSM
    
    Arbiter --> Bridge
    Bridge -->|io_master_*| External["外部 AXI4"]
```

### 2.2 EXU 执行单元状态机

EXU 是 NPC 的核心执行单元，采用多周期状态机设计。

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> DECODE: op_en
    DECODE --> EXECUTE: 译码完成
    EXECUTE --> WAIT_LSU: Load/Store指令
    EXECUTE --> WRITEBACK: 其他指令
    WAIT_LSU --> WRITEBACK: lsu_rvalid
    WRITEBACK --> IDLE: 写回完成
```

**状态说明：**

| 状态 | 说明 |
|------|------|
| IDLE | 等待指令有效（op_en） |
| DECODE | 指令译码，准备操作数 |
| EXECUTE | ALU 运算、分支计算、访存地址计算 |
| WAIT_LSU | 等待 Load/Store 完成 |
| WRITEBACK | 写回寄存器、更新 PC |

### 2.3 ICache 状态机

ICache 采用 2-way 组相联设计，4KB 容量，LRU 替换策略。

```mermaid
stateDiagram-v2
    [*] --> S_IDLE
    S_IDLE --> S_LOOKUP: cpu_req
    S_LOOKUP --> S_IDLE: hit
    S_LOOKUP --> S_REFILL: miss
    S_REFILL --> S_IDLE: mem_rvalid
```

**ICache 参数：**

| 参数 | 数值 | 说明 |
|------|------|------|
| 总大小 | 4 KB | 平衡面积与命中率 |
| 关联度 | 2-way | 降低冲突 miss |
| 块大小 | 4 Bytes | 1 word，简化 refill |
| 组数 | 512 sets | 4KB / 2-way / 4B |
| 地址划分 | Tag[31:11] Index[10:2] | 21-bit tag, 9-bit index |
| 替换策略 | LRU | 每组 1 bit |

### 2.4 IFU_AXI 状态机

IFU_AXI 负责从内存获取指令，采用显式三状态机设计。

```mermaid
stateDiagram-v2
    [*] --> IFU_IDLE
    IFU_IDLE --> IFU_WAIT_AR: req
    IFU_WAIT_AR --> IFU_WAIT_R: arready
    IFU_WAIT_R --> IFU_IDLE: rvalid
```

### 2.5 AXI4-Lite Arbiter 状态机

仲裁器管理 IFU 和 LSU 对总线的访问，IFU 具有更高优先级。

```mermaid
stateDiagram-v2
    [*] --> ARB_IDLE
    ARB_IDLE --> ARB_IFU: ifu_req
    ARB_IDLE --> ARB_LSU: lsu_req & !ifu_req
    ARB_IFU --> ARB_IDLE: 事务完成
    ARB_LSU --> ARB_IDLE: 事务完成
```

**仲裁策略：**
- IFU (Master 0) 优先级高于 LSU (Master 1)
- 事务完成条件：读 `rvalid && rready` 或写 `bvalid && bready`

---

## 3. 模块详细说明

### 3.1 核心模块 (`npc/vsrc/core/`)

| 模块 | 文件 | 功能 |
|------|------|------|
| EXU | `EXU.v` | 指令译码、ALU、分支、CSR、LSU 控制 |
| ICache | `ICache.v` | 2-way 4KB 指令缓存，LRU 替换 |
| IFU_AXI | `IFU_AXI.v` | 取指 AXI4-Lite Master，3 状态机 |
| LSU_AXI | `LSU_AXI.v` | 访存 AXI4-Lite Master，支持字节/半字/字 |
| Arbiter | `AXI4_Lite_Arbiter.v` | IFU/LSU 请求仲裁，IFU 优先 |
| Bridge | `AXI4_Lite_to_AXI4_Bridge.v` | AXI4-Lite → AXI4 协议转换 |
| RegFile | `RegisterFile.v` | 通用寄存器文件 (x0-x15) |

### 3.2 EXU 支持的指令

| 类型 | 指令 |
|------|------|
| R 型 | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| I 型 | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Load | LB, LH, LW, LBU, LHU |
| Store | SB, SH, SW |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jump | JAL, JALR |
| 其他 | LUI, AUIPC, FENCE, CSR, ECALL, EBREAK |

### 3.3 关键信号流

```mermaid
sequenceDiagram
    participant PC as PC寄存器
    participant ICache as ICache
    participant IFU as IFU_AXI
    participant Arb as Arbiter
    participant SoC as ysyxSoC
    participant EXU as EXU
    participant LSU as LSU_AXI
    
    PC->>ICache: ifu_req, ifu_addr
    alt Cache Hit
        ICache-->>EXU: ifu_rvalid, ifu_rdata (2 cycles)
    else Cache Miss
        ICache->>IFU: mem_req, mem_addr
        IFU->>Arb: AR channel
        Arb->>SoC: AXI4 AR
        SoC-->>Arb: AXI4 R (~750 cycles)
        Arb-->>IFU: R channel
        IFU-->>ICache: mem_rvalid, mem_rdata
        ICache-->>EXU: ifu_rvalid, ifu_rdata
    end
    
    EXU->>LSU: lsu_req, lsu_addr
    LSU->>Arb: AR/AW channel
    Arb->>SoC: AXI4 AR/AW
    SoC-->>Arb: AXI4 R/B (~150 cycles)
    Arb-->>LSU: R/B channel
    LSU-->>EXU: lsu_rvalid, lsu_rdata
```

---

## 4. ysyxSoC 架构

### 4.1 总线层次

ysyxSoC 采用两层总线架构：AXI4 主总线 + APB 外设总线。

```mermaid
graph TB
    CPU["NPC CPU<br/>AXI4 Master"] --> Xbar["AXI4 Xbar"]
    
    Xbar --> Xbar2["AXI4 Xbar2"]
    Xbar --> SDRAM_AXI["SDRAM<br/>AXI4 可选"]
    
    Xbar2 --> MROM["MROM<br/>0x20000000"]
    Xbar2 --> SRAM["SRAM<br/>0x0f000000"]
    Xbar2 --> AXI2APB["AXI4ToAPB"]
    
    AXI2APB --> APB["APB Fanout"]
    
    APB --> UART["UART<br/>0x10000000"]
    APB --> SPI["SPI<br/>0x10001000"]
    APB --> GPIO["GPIO<br/>0x10002000"]
    APB --> PS2["PS/2<br/>0x10011000"]
    APB --> VGA["VGA<br/>0x21000000"]
    APB --> Flash["Flash<br/>0x30000000"]
    APB --> PSRAM["PSRAM<br/>0x80000000"]
    APB --> SDRAM_APB["SDRAM<br/>0xa0000000"]
```

### 4.2 地址映射表

| 设备 | 起始地址 | 大小 | 总线 | 说明 |
|------|---------|------|------|------|
| SRAM | 0x0f000000 | 8KB | AXI4 | 片内 SRAM，栈与数据 |
| UART | 0x10000000 | 4KB | APB | 16550 兼容串口 |
| SPI | 0x10001000 | 4KB | APB | SPI 控制器 |
| GPIO | 0x10002000 | 16B | APB | 通用 IO |
| PS/2 | 0x10011000 | 8B | APB | 键盘接口 |
| MROM | 0x20000000 | 4KB | AXI4 | Boot ROM，复位入口 |
| VGA | 0x21000000 | 2MB | APB | 帧缓冲 |
| Flash | 0x30000000 | 256MB | APB | XIP Flash，程序存储 |
| PSRAM | 0x80000000 | 4MB | APB | QSPI PSRAM，主内存 |
| SDRAM | 0xa0000000 | 32MB | APB/AXI | 大容量动态内存 |

### 4.3 启动流程

```mermaid
graph LR
    Reset["复位"] --> MROM["MROM<br/>0x20000000"]
    MROM --> Flash["Flash XIP<br/>0x30000000"]
    Flash --> Copy["拷贝到 PSRAM<br/>0x80000000"]
    Copy --> Run["运行程序"]
```

1. **复位后**: PC = 0x20000000 (MROM)
2. **MROM**: 包含 bootloader，跳转到 Flash
3. **Flash**: 从 Flash XIP 读取程序
4. **拷贝**: 将 .data 段拷贝到 PSRAM
5. **运行**: 在 PSRAM 中执行程序

---

## 5. AXI 协议栈

### 5.1 协议转换层次

```mermaid
graph TB
    subgraph NPC_Internal ["NPC 内部"]
        IFU["IFU_AXI<br/>AXI4-Lite Master"]
        LSU["LSU_AXI<br/>AXI4-Lite Master"]
    end
    
    subgraph Arbiter_Layer ["仲裁层"]
        ARB["AXI4_Lite_Arbiter<br/>M0: IFU 优先<br/>M1: LSU"]
    end
    
    subgraph Bridge_Layer ["桥接层"]
        BRG["AXI4_Lite_to_AXI4_Bridge<br/>添加 ID/LEN/SIZE/BURST"]
    end
    
    subgraph SoC_Bus ["ysyxSoC 总线"]
        XBAR["AXI4 Xbar<br/>地址路由"]
        A2A["AXI4ToAPB<br/>协议转换"]
    end
    
    IFU --> ARB
    LSU --> ARB
    ARB --> BRG
    BRG --> XBAR
    XBAR --> A2A
```

### 5.2 AXI4-Lite vs AXI4

| 特性 | AXI4-Lite | AXI4 |
|------|-----------|------|
| 突发传输 | 不支持 | 支持 (LEN, BURST) |
| 事务 ID | 不支持 | 支持 (ID) |
| 传输大小 | 固定 4B | 可变 (SIZE) |
| 复杂度 | 低 | 高 |

**Bridge 转换规则：**
- `awlen/arlen = 0` (单次传输)
- `awsize/arsize = 2` (4 字节)
- `awburst/arburst = 01` (INCR)
- `awid/arid = 0`

### 5.3 AXI4 通道说明

| 通道 | 方向 | 功能 |
|------|------|------|
| AW (Write Address) | Master → Slave | 写地址和控制信息 |
| W (Write Data) | Master → Slave | 写数据和字节选通 |
| B (Write Response) | Slave → Master | 写响应 |
| AR (Read Address) | Master → Slave | 读地址和控制信息 |
| R (Read Data) | Slave → Master | 读数据和响应 |

---

## 6. 关键文件列表

### 6.1 NPC 处理器

| 文件 | 说明 |
|------|------|
| `npc/vsrc/ysyx_00000000.v` | CPU 顶层模块 |
| `npc/vsrc/core/EXU.v` | 执行单元 |
| `npc/vsrc/core/ICache.v` | 指令缓存 |
| `npc/vsrc/core/IFU_AXI.v` | 取指 AXI 接口 |
| `npc/vsrc/core/LSU_AXI.v` | 访存 AXI 接口 |
| `npc/vsrc/core/AXI4_Lite_Arbiter.v` | 总线仲裁器 |
| `npc/vsrc/core/AXI4_Lite_to_AXI4_Bridge.v` | 协议桥接 |
| `npc/vsrc/core/RegisterFile.v` | 寄存器文件 |

### 6.2 ysyxSoC

| 文件 | 说明 |
|------|------|
| `ysyxSoC/src/SoC.scala` | SoC 顶层 |
| `ysyxSoC/src/CPU.scala` | CPU 接口定义 |
| `ysyxSoC/src/Xbar.scala` | 总线交叉开关 |
| `ysyxSoC/src/AXI4ToAPB.scala` | AXI4 到 APB 桥 |
| `ysyxSoC/src/device/UART16550.scala` | UART 控制器 |
| `ysyxSoC/src/device/SPI.scala` | SPI 控制器 |
| `ysyxSoC/src/device/PSRAM.scala` | PSRAM 控制器 |
| `ysyxSoC/src/device/SDRAM.scala` | SDRAM 控制器 |
| `ysyxSoC/src/device/VGA.scala` | VGA 控制器 |

### 6.3 仿真与构建

| 文件 | 说明 |
|------|------|
| `npc/Makefile.soc` | SoC 仿真 Makefile |
| `npc/csrc/main_soc.cpp` | 仿真主程序 |
| `ysyxSoC/build.sbt` | SoC 构建配置 |

---

## 7. 性能数据

### 7.1 基线 vs ICache 优化

| 指标 | 无 ICache | 有 ICache | 提升 |
|------|-----------|-----------|------|
| CPI | 950.64 | 55.33 | **17.18x** |
| 取指延迟 | ~900 cycles | 2 cycles (hit) | - |
| ICache 命中率 | - | 98.78% | - |

### 7.2 访存延迟

| 操作 | 延迟 (cycles) |
|------|--------------|
| ICache Hit | 2 |
| ICache Miss (Refill) | ~746 |
| Load (PSRAM) | ~182 |
| Store (PSRAM) | ~117 |

---

## 8. 学习建议

1. **先理解数据通路**: 从 EXU 开始，理解指令如何执行
2. **再学习总线接口**: 理解 AXI4-Lite 协议和握手机制
3. **然后研究缓存**: 理解 ICache 如何提升性能
4. **最后看 SoC 集成**: 理解外设如何访问

**推荐阅读顺序:**
1. `EXU.v` - 核心执行逻辑
2. `IFU_AXI.v` / `LSU_AXI.v` - AXI 接口
3. `AXI4_Lite_Arbiter.v` - 仲裁机制
4. `ICache.v` - 缓存设计
5. `ysyx_00000000.v` - 顶层集成
