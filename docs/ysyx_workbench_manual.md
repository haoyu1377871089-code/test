# ysyx-workbench 开发手册 (Developer Manual)

本文档整合了 ysyx 工作台的技术细节、架构说明、集成指南以及开发任务清单。

## 目录 (Table of Contents)

1.  [架构概览 (Architecture Overview)](#1-架构概览-architecture-overview)
    *   [系统组成](#11-系统组成)
    *   [构建配置 (riscv32e-ysyxsoc)](#12-构建配置-riscv32e-ysyxsoc)
2.  [内存布局与链接 (Memory & Linking)](#2-内存布局与链接-memory--linking)
    *   [系统内存映射](#21-系统内存映射-memory-map)
    *   [链接脚本详解](#22-链接脚本详解-linker_ysyxsocld)
3.  [Abstract Machine 详解](#3-abstract-machine-详解)
    *   [源文件清单](#31-源文件清单)
4.  [NPC 设计与验证](#4-npc-设计与验证)
    *   [模块实例化说明](#41-模块实例化说明)
    *   [Flash 测试全流程解析](#42-flash-测试全流程解析)
5.  [ysyxSoC 集成指南](#5-ysyxsoc-集成指南)
    *   [接口要求](#51-接口要求-cpu-interface)
    *   [外设开发需求](#52-外设开发需求)
    *   [开发任务清单](#53-开发任务清单)

---

## 1. 架构概览 (Architecture Overview)

### 1.1 系统组成
ysyx-workbench 是一个软硬件协同设计的全系统环境，核心包含：
*   **NPC**: 自研 RISC-V 处理器核 (Verilog)。
*   **ysyxSoC**: 基于 Chisel 生成的 SoC 总线与外设架构。
*   **Abstract Machine (AM)**: 硬件抽象层，用于编写裸机程序。

### 1.2 构建配置 (riscv32e-ysyxsoc)

当指定 `ARCH=riscv32e-ysyxsoc` 时，AM 构建系统会加载特定的配置，将通用的 RISC-V 设置“特化”为 32位嵌入式版本 (RV32E)，并绑定到 ysyxSoC 硬件平台。

**核心配置 (`scripts/riscv32e-ysyxsoc.mk`)**:
*   **ISA**: `rv32e_zicsr` (E扩展：仅16个通用寄存器)。
*   **ABI**: `ilp32e`。
*   **宏定义**: `-DISA_H="riscv/riscv.h"`。
*   **启动代码**: `riscv/ysyxsoc/start.S`。

---

## 2. 内存布局与链接 (Memory & Linking)

### 2.1 系统内存映射 (Memory Map)

参考 `ysyxSoC/src/SoC.scala`，系统地址空间分配如下：

| 设备 (Device) | 起始地址 (Start) | 大小 (Size) | 类型 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| **SRAM** | `0x0f000000` | `0x2000` (8KB) | AXI4 | 片内 SRAM，用于数据与堆栈 |
| **UART** | `0x10000000` | `0x1000` | APB | 16550 兼容串口 |
| **SPI Ctrl** | `0x10001000` | `0x1000` | APB | SPI 控制器寄存器 |
| **GPIO** | `0x10002000` | `0x10` | APB | 通用输入输出 (需实现) |
| **PS/2** | `0x10011000` | `0x8` | APB | 键盘接口 (需实现) |
| **MROM** | `0x20000000` | `0x1000` | AXI4 | Boot ROM，复位入口 |
| **VGA** | `0x21000000` | `2MB` | APB | 帧缓冲 (需实现) |
| **Flash (XIP)**| `0x30000000` | `256MB` | APB | 映射至 SPI Flash，支持直接取指 |
| **PSRAM** | `0x80000000` | `4MB` | APB | QSPI 接口扩展内存 |
| **SDRAM** | `0xa0000000` | `32MB` | APB/AXI | 大容量动态内存 |

### 2.2 链接脚本详解 (`linker_ysyxsoc.ld`)

链接脚本定义了典型的嵌入式布局：**代码在 ROM 中原地执行 (XIP)，数据从 ROM 搬运到 RAM 中使用。**

*   **MROM (`0x20000000`)**: 
    *   存放 `.text` (代码) 和 `.rodata` (只读数据)。
    *   LMA (加载地址) = VMA (运行地址)。
*   **SRAM (`0x0f000000`)**: 
    *   存放 `.data` (读写变量) 和 `.bss` (未初始化变量)。
    *   `.data` 的 **LMA** 在 MROM 中 (紧跟 rodata)，**VMA** 在 SRAM 中。
    *   启动代码 (`trm.c`) 负责将数据从 MROM 搬运至 SRAM。

**启动流程**:
1.  CPU 复位至 `0x20000000` (MROM)。
2.  执行 `start.S`，设置栈指针 `sp` 指向 SRAM 末尾。
3.  跳转至 `_trm_init`。
4.  初始化 UART，搬运 `.data`，清零 `.bss`。
5.  跳转至用户 `main` 函数。

---

## 3. Abstract Machine 详解

### 3.1 源文件清单

编译 `ARCH=riscv32e-ysyxsoc` 时包含的主要文件：

**平台特定 (ysyxSoC)**:
*   `am/src/riscv/ysyxsoc/start.S`: 汇编启动入口。
*   `am/src/platform/ysyxsoc/trm.c`: 运行时管理 (串口输出, Halt)。
*   `am/src/platform/ysyxsoc/ioe/ioe.c`: IO 扩展支持。

**通用库 (klib)**:
*   `string.c`: `memcpy`, `memset`, `strcpy` 等。
*   `stdio.c`: `printf`, `sprintf` 等。
*   `stdlib.c`: `malloc`, `free`, `rand` 等。

---

## 4. NPC 设计与验证

### 4.1 模块实例化说明

NPC (`npc/vsrc/top.v`) 顶层集成了以下核心模块：
*   **IFU_SRAM**: 指令取指单元，通过 AXI4/AXI4-Lite 读取指令。
*   **EXU**: 执行单元，包含译码、ALU、分支跳转逻辑。
*   **LSU_SRAM**: 访存单元，处理数据读写请求。
*   **RegisterFile**: 32个通用寄存器堆。

### 4.2 Flash 测试全流程解析

`flash-test` (`am-kernels/tests/cpu-tests/tests/flash-test.c`) 是验证 SoC 总线访问的关键测试。

**执行流程**:
1.  **加载**: 仿真器 (`main_soc.cpp`) 加载测试镜像到 MROM (`0x20000000`) 和 Flash (`0x30000000`)。
2.  **取指**: NPC 从 MROM 获取指令。
3.  **访存**: 指令 `lw a0, 0(a5)` 访问 `0x30000000`。
4.  **路由**: SoC Crossbar 将请求路由至 SPI 控制器。
5.  **转换**: SPI 控制器将 AXI 请求转换为 SPI 协议 (SCK, MOSI)。
6.  **模型**: Verilog Flash 模型通过 DPI-C 调用 C++ `flash_read` 读取数据。
7.  **回传**: 数据经由 SPI MISO -> SPI 控制器 -> AXI R-Channel -> NPC LSU。
8.  **验证**: NPC 比较读取值，若为 `0xdeadbeef` 则测试通过。

---

## 5. ysyxSoC 集成指南

### 5.1 接口要求 (CPU Interface)

NPC 必须提供完整的 **AXI4 Master** 接口以接入 SoC：
*   **Global**: `clock`, `reset`, `io_interrupt`
*   **AW (写地址)**: `id`, `addr`, `len`, `size`, `burst`, `valid`, `ready`
*   **W (写数据)**: `data`, `strb`, `last`, `valid`, `ready`
*   **B (写响应)**: `id`, `resp`, `valid`, `ready`
*   **AR (读地址)**: `id`, `addr`, `len`, `size`, `burst`, `valid`, `ready`
*   **R (读数据)**: `id`, `data`, `resp`, `last`, `valid`, `ready`

### 5.2 外设开发需求

ysyxSoC 提供了外设的空壳 (`perip/`), 需补充 RTL 实现：
1.  **GPIO**: 实现 `GPIO_OUT` (LED), `GPIO_IN` (Switch), `GPIO_SEG` (数码管)。
2.  **PS/2**: 实现键盘扫描码 FIFO。
3.  **VGA**: 实现帧缓冲读取与时序生成。
4.  **SPI XIP**: 在 SPI 控制器中实现自动读取 Flash 的逻辑 (Hardware Fetch)。

### 5.3 开发任务清单

**已完成**:
- [x] 配置 `riscv32e-ysyxsoc` AM 环境。
- [x] 修复 `LSU_SRAM` 的 AXI 握手逻辑。
- [x] 实现 Flash 和 MROM 的 C++ 仿真模型 (DPI-C)。
- [x] 成功运行 `flash-test`。

**待办 (To-Do)**:
- [ ] **接口升级**: 将 NPC 接口从 AXI4-Lite 升级为全功能 AXI4。
- [ ] **外设实现**: 编写 GPIO, PS/2, VGA 的 Verilog 代码。
- [ ] **驱动开发**: 在 AM 中添加对应外设的驱动程序。
- [ ] **Flash XIP**: 实现 SPI 控制器的 XIP 模式，使 NPC 能直接从 Flash 启动 (`0x30000000`)。
- [ ] **大容量存储**: 实现 PSRAM/SDRAM 控制器与仿真模型。
- [ ] **系统集成**: 移植 RT-Thread 或其他 OS。

---
*Created by Gemini CLI - 2025*
