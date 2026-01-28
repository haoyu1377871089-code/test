# NPC Verilog 源代码目录

本目录包含 NPC (New Processor Core) 的 Verilog 源代码，分为两个独立配置。

## 目录结构

```
vsrc/
├── npc_soc/              # 独立仿真配置 (使用内部 SRAM/UART/CLINT)
│   ├── npc_soc_top.v     # 顶层模块 (module top)
│   ├── EXU.v             # 执行单元
│   ├── RegisterFile.v    # 寄存器文件
│   ├── IFU_SRAM.v        # 取指单元 (AXI4-Lite Master)
│   ├── LSU_SRAM.v        # 访存单元 (AXI4-Lite Master)
│   ├── AXI4_Lite_Arbiter.v # AXI4-Lite 仲裁器
│   ├── AXI4_Lite_Xbar.v  # AXI4-Lite 交叉开关
│   ├── AXI4_Lite_SRAM.v  # SRAM 从设备
│   ├── AXI4_Lite_UART.v  # UART 从设备
│   ├── AXI4_Lite_CLINT.v # CLINT 从设备
│   └── MEM.v             # 内存模块
│
├── ysyxsoc/              # ysyxSoC 配置 (使用外部 AXI4 总线)
│   ├── ysyx_00000000.v   # 顶层模块 (NPC Core)
│   ├── EXU.v             # 执行单元
│   ├── RegisterFile.v    # 寄存器文件
│   ├── ICache.v          # 指令缓存 (4KB, 2-way, 16B line)
│   ├── DCache.v          # 数据缓存 (4KB, 2-way, 16B line, write-through)
│   ├── IFU_AXI4.v        # 取指单元 (AXI4 Burst Master)
│   ├── LSU_AXI4.v        # 访存单元 (AXI4 Master, 支持 Burst)
│   └── AXI4_Arbiter.v    # AXI4 仲裁器 (支持 Burst)
│
└── README.md
```

## 配置说明

### npc_soc/ - 独立仿真配置

用于不依赖 ysyxSoC 的独立仿真和测试。

**特点：**
- 内置 SRAM、UART、CLINT 外设
- 使用 AXI4-Lite 总线协议
- 适合单元测试和快速验证

**编译方式：**
```bash
cd npc
make         # 使用 Makefile (独立仿真)
```

### ysyxsoc/ - ysyxSoC 配置

用于集成到 ysyxSoC 系统中，连接真实外设。

**特点：**
- 使用 AXI4 总线协议 (支持 Burst)
- 包含 I-Cache (4KB, 2-way, 16B cache line)
- 包含 D-Cache (4KB, 2-way, 16B cache line, write-through)
- 连接 ysyxSoC 的 SDRAM、Flash、UART 等外设

**编译方式：**
```bash
cd npc
make -f Makefile.soc   # 使用 Makefile.soc (ysyxSoC)
```

## 已删除的废弃文件

以下文件已被删除，因为两种配置都不再使用：

| 文件 | 说明 |
|------|------|
| `IFU_AXI.v` | 旧的 AXI4-Lite IFU，已被 IFU_AXI4.v 替代 |
| `LSU_AXI.v` | 旧的 AXI4-Lite LSU，已被 LSU_AXI4.v 替代 |
| `AXI4_Lite_to_AXI4_Bridge.v` | 旧的协议桥接，已不需要 |

## 模块说明

### 共享模块 (两个配置各有一份副本)

| 模块 | 说明 |
|------|------|
| `EXU.v` | 执行单元，包含 ALU、分支判断、CSR |
| `RegisterFile.v` | 参数化寄存器文件 |

### ysyxsoc 专用模块

| 模块 | 说明 |
|------|------|
| `ysyx_00000000.v` | NPC 核心顶层，AXI4 Master 接口 |
| `ICache.v` | 2-way 组相联 I-Cache，支持 Burst refill |
| `DCache.v` | 2-way 组相联 D-Cache，write-through + no-write-allocate |
| `IFU_AXI4.v` | AXI4 Master，支持 4-beat burst |
| `LSU_AXI4.v` | AXI4 Master，支持单拍和 burst 读写 |
| `AXI4_Arbiter.v` | AXI4 仲裁器，IFU 优先 |

### npc_soc 专用模块

| 模块 | 说明 |
|------|------|
| `npc_soc_top.v` | 独立仿真顶层 |
| `IFU_SRAM.v` | AXI4-Lite Master IFU |
| `LSU_SRAM.v` | AXI4-Lite Master LSU |
| `AXI4_Lite_Arbiter.v` | AXI4-Lite 仲裁器 |
| `AXI4_Lite_Xbar.v` | 地址译码交叉开关 |
| `AXI4_Lite_SRAM.v` | SRAM 从设备 |
| `AXI4_Lite_UART.v` | UART 从设备 |
| `AXI4_Lite_CLINT.v` | CLINT 从设备 |
| `MEM.v` | 底层内存模块 |

## 性能参数 (ysyxsoc 配置)

### I-Cache

| 参数 | 值 |
|------|-----|
| I-Cache 大小 | 4 KB |
| I-Cache 关联度 | 2-way |
| Cache Line 大小 | 16 Bytes |
| AXI4 Burst 长度 | 4-beat (16 Bytes) |
| Hit Rate (microbench) | 99.67% |
| AMAT | 11.65 cycles |

### D-Cache

| 参数 | 值 |
|------|-----|
| D-Cache 大小 | 4 KB |
| D-Cache 关联度 | 2-way |
| Cache Line 大小 | 16 Bytes |
| 写策略 | Write-through + No-write-allocate |
| AXI4 Burst 长度 | 4-beat (16 Bytes) for refill |

## 编译选项

在 `Makefile.soc` 中可以通过 `+define+` 控制功能：

| 选项 | 说明 |
|------|------|
| `SIMULATION` | 启用仿真专用功能（性能计数器等） |
| `ENABLE_ICACHE` | 启用 I-Cache |
| `ENABLE_DCACHE` | 启用 D-Cache |
