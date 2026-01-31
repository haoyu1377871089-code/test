# YSYX Workbench - RISC-V CPU 软硬件协同开发环境

一站式 RISC-V 处理器设计与验证平台，源自"一生一芯"(YSYX) 项目。支持从 RTL 设计、功能仿真到 SoC 集成的完整开发流程。

## 目录

- [项目概述](#项目概述)
- [Ubuntu 22.04 完整搭建教程](#ubuntu-2204-完整搭建教程)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [模块介绍](#模块介绍)
- [构建与运行](#构建与运行)
- [项目结构](#项目结构)

## 项目概述

本项目提供完整的 RISC-V CPU 软硬件协同开发环境，主要特性：

- **处理器设计**：支持多周期和五级流水线两种微架构
- **功能验证**：通过 DiffTest 与参考模型 (NEMU) 进行差分测试
- **SoC 集成**：基于 AXI4 总线的完整 SoC 框架
- **可视化调试**：NVBoard 虚拟板卡支持 VGA、键盘、LED 等外设
- **丰富测试集**：从基础指令测试到 Benchmark 性能评估

---

## Ubuntu 22.04 完整搭建教程

本教程将指导你在全新的 Ubuntu 22.04 系统上从零开始搭建项目，并最终运行 RT-Thread 实时操作系统。

### 第一步：安装系统依赖

```bash
# 更新包管理器
sudo apt update && sudo apt upgrade -y

# 基础开发工具
sudo apt install -y build-essential git gdb-multiarch ccache

# RISC-V 交叉编译工具链
sudo apt install -y gcc-riscv64-linux-gnu g++-riscv64-linux-gnu binutils-riscv64-linux-gnu

# SDL2 库（用于 NVBoard 可视化和设备仿真）
sudo apt install -y libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libsdl2-mixer-dev

# Java 运行时（Mill 构建工具依赖）
sudo apt install -y default-jdk

# 其他工具
sudo apt install -y device-tree-compiler flex bison libreadline-dev python3 curl
```

### 第二步：安装 Verilator (v5.0+)

Ubuntu 22.04 的 apt 仓库中 Verilator 版本较老，建议从源码编译安装：

```bash
# 安装 Verilator 编译依赖
sudo apt install -y autoconf help2man perl python3 make g++ libfl2 libfl-dev zlib1g zlib1g-dev

# 下载并编译 Verilator
cd /tmp
git clone https://github.com/verilator/verilator.git
cd verilator
git checkout v5.008  # 推荐版本

# 配置并编译（约需 5-10 分钟）
autoconf
./configure
make -j$(nproc)
sudo make install

# 验证安装
verilator --version
# 应输出: Verilator 5.008 ...
```

### 第三步：安装 Mill 构建工具

**注意：不要使用 `sudo snap install mill`，那是一个棋盘游戏，不是构建工具！**

```bash
# 下载并安装 Mill 构建工具
curl -L https://raw.githubusercontent.com/lefou/millw/0.4.11/millw > /tmp/mill
chmod +x /tmp/mill
sudo mv /tmp/mill /usr/local/bin/mill

# 验证安装
mill --version
# 应输出: Mill Build Tool version 0.12.x
```

### 第四步：克隆项目并设置环境变量

```bash
# 克隆项目（假设克隆到 ~/ysyx-workbench）
cd ~
git clone <your-repo-url> ysyx-workbench
cd ysyx-workbench

# 设置环境变量（添加到 ~/.bashrc）
echo 'export NEMU_HOME=~/ysyx-workbench/nemu' >> ~/.bashrc
echo 'export AM_HOME=~/ysyx-workbench/abstract-machine' >> ~/.bashrc
echo 'export NPC_HOME=~/ysyx-workbench/npc' >> ~/.bashrc
echo 'export NVBOARD_HOME=~/ysyx-workbench/nvboard' >> ~/.bashrc

# 使环境变量生效
source ~/.bashrc

# 验证环境变量
echo $AM_HOME  # 应输出: /home/<用户名>/ysyx-workbench/abstract-machine
```

### 第五步：初始化 ysyxSoC 子模块

```bash
cd ~/ysyx-workbench/ysyxSoC

# 初始化子模块
make dev-init

# 生成 SoC Verilog（首次编译约需 2-3 分钟）
make verilog

# 验证生成
ls -la build/ysyxSoCFull.v
# 应看到生成的 Verilog 文件
```

### 第六步：构建 NPC 处理器仿真

```bash
cd ~/ysyx-workbench/npc

# 构建流水线版本（推荐）
make -f Makefile.soc pipeline

# 验证构建
ls -la build_soc/ysyxSoCFull
# 应看到可执行文件
```

### 第七步：编译并运行 RT-Thread

```bash
cd ~/ysyx-workbench/rt-thread-am/bsp/abstract-machine

# 编译 RT-Thread
make ARCH=riscv32e-ysyxsoc

# 运行 RT-Thread
make ARCH=riscv32e-ysyxsoc run
```

成功运行后，你应该看到类似以下输出：

```
 \ | /
- RT -     Thread Operating System
 / | \     5.0.0 build Jan 31 2026 17:00:00
 2006 - 2022 Copyright by RT-Thread team
msh >
```

### 第八步：运行 CPU 测试（可选）

```bash
cd ~/ysyx-workbench/am-kernels/tests/cpu-tests

# 运行单个测试
make ARCH=riscv32e-ysyxsoc ALL=add run

# 运行所有 CPU 测试
make ARCH=riscv32e-ysyxsoc run
```

### 常见问题排查

1. **`stddef.h: No such file or directory`**
   - 检查 RISC-V 工具链是否正确安装：`riscv64-linux-gnu-gcc --version`
   - 确保安装了 `gcc-riscv64-linux-gnu`

2. **`mill` 命令卡住或显示游戏界面**
   - 你可能安装了错误的 snap 包，运行 `sudo snap remove mill`
   - 按照第三步重新安装正确的 Mill 构建工具

3. **Verilator 版本过低**
   - Ubuntu apt 仓库的版本可能较老，建议从源码编译 v5.0+

4. **NVBoard 窗口不显示（WSL2 用户）**
   - WSL2 需要 X Server 支持，安装 VcXsrv 或使用 WSLg
   - 设置 `export DISPLAY=:0`（WSLg）或 `export DISPLAY=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):0`（VcXsrv）

---

## 环境要求

### 操作系统

- Linux (推荐 Ubuntu 20.04 / 22.04)
- WSL2 (Windows Subsystem for Linux)

### 依赖工具

```bash
# 基础开发工具
sudo apt install build-essential git gdb-multiarch ccache

# RISC-V 交叉编译工具链
sudo apt install gcc-riscv64-linux-gnu g++-riscv64-linux-gnu

# Verilator 仿真器 (推荐 v5.0+，建议源码编译)
# 见上方完整搭建教程

# SDL2 库 (NVBoard 可视化)
sudo apt install libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev

# Java 运行时 (Mill 构建工具)
sudo apt install default-jdk

# 其他工具
sudo apt install device-tree-compiler flex bison libreadline-dev
```

### 环境变量

设置以下环境变量（添加到 `~/.bashrc`）：

```bash
export NEMU_HOME=/path/to/nemu
export AM_HOME=/path/to/abstract-machine
export NPC_HOME=/path/to/npc
export NVBOARD_HOME=/path/to/nvboard
```

配置完成后，执行 `source ~/.bashrc` 使环境变量生效。

## 快速开始

> 如果你是第一次搭建环境，请先阅读 [Ubuntu 22.04 完整搭建教程](#ubuntu-2204-完整搭建教程)。

### 1. 构建 NPC 处理器

```bash
cd npc

# 流水线版本（推荐）
make -f Makefile.soc pipeline

# 多周期版本
make -f Makefile.soc soc

# 带 NVBoard 可视化的流水线版本
make -f Makefile.soc nvboard-pipeline
```

### 2. 运行 CPU 测试

```bash
cd am-kernels/tests/cpu-tests

# 运行单个测试
make ARCH=riscv32e-ysyxsoc ALL=add run

# 运行所有测试
make ARCH=riscv32e-ysyxsoc run
```

### 3. 运行 RT-Thread

```bash
cd rt-thread-am/bsp/abstract-machine

# 编译
make ARCH=riscv32e-ysyxsoc

# 运行
make ARCH=riscv32e-ysyxsoc run
```

### 4. 运行 Benchmark

```bash
cd am-kernels/benchmarks/coremark
make ARCH=riscv32e-ysyxsoc run
```

### 5. 编译 NEMU 参考模型（可选，用于 DiffTest）

```bash
cd nemu
make riscv32-am_defconfig  # 使用预设配置
make                        # 编译
```

## 模块介绍

### npc/ - 处理器核心 (New Processor Core)

自主设计的 RISC-V 处理器核心，基于 Verilog 实现。

```
npc/
├── vsrc/                # Verilog 源码
│   ├── npc_soc/        # 独立仿真配置 (AXI4-Lite)
│   └── ysyxsoc/        # SoC 集成配置 (AXI4)
│       └── pipeline/   # 五级流水线版本
├── csrc/               # C++ 仿真顶层 (Verilator)
│   └── dev/            # 外设仿真 (VGA, 键盘等)
├── Makefile            # 独立仿真构建
└── Makefile.soc        # ysyxSoC 构建
```

**关键特性**：
- 双配置架构：独立仿真 (npc_soc) 和 SoC 集成 (ysyxsoc)
- 多周期与五级流水线两种实现
- I-Cache 支持（4KB, 2-way 组相联）
- AXI4 Burst 传输

**构建选项**：
```bash
make -f Makefile.soc soc              # 多周期版本
make -f Makefile.soc pipeline         # 流水线版本
make -f Makefile.soc nvboard          # 多周期 + NVBoard
make -f Makefile.soc nvboard-pipeline # 流水线 + NVBoard
```

### nemu/ - 参考模型模拟器

NEMU (NJU Emulator) 是教学用的 RISC-V 解释器，作为"黄金模型"与 NPC 进行 DiffTest 验证。

```
nemu/
├── src/
│   ├── cpu/           # CPU 执行引擎
│   │   └── difftest/  # DiffTest 实现
│   ├── isa/           # 多 ISA 支持 (riscv32/64, x86, mips32)
│   ├── memory/        # 内存子系统
│   ├── device/        # 外设模拟
│   └── monitor/       # 监控器与调试器 (SDB)
├── configs/           # 预配置文件
├── Kconfig            # 配置系统
└── Makefile
```

**主要功能**：
- 多 ISA 支持：RISC-V (32/64), x86, MIPS32, LoongArch32r
- DiffTest：与外部 DUT 进行差分测试
- 内置调试器 (SDB)：支持单步、断点、监视点
- 设备模拟：串口、定时器、键盘、VGA、音频

**常用命令**：
```bash
make menuconfig  # 配置
make             # 编译
make run         # 运行
```

### abstract-machine/ - 硬件抽象层

Abstract Machine (AM) 是裸机编程的硬件抽象层，实现"一次编写，到处运行"。

```
abstract-machine/
├── am/
│   ├── include/       # API 定义 (am.h, amdev.h)
│   └── src/           # 各架构/平台实现
│       ├── riscv/     # RISC-V 实现
│       │   ├── npc/   # NPC 平台
│       │   ├── nemu/  # NEMU 平台
│       │   └── ysyxsoc/ # ysyxSoC 平台
│       └── native/    # Linux 原生平台
├── klib/              # 内核库 (printf, malloc, string 等)
└── scripts/           # 构建脚本与链接脚本
```

**抽象层级**：
- **TRM** (Turing Machine)：基本计算环境
- **IOE** (I/O Extension)：输入输出设备
- **CTE** (Context Extension)：中断/异常处理
- **VME** (Virtual Memory Extension)：虚拟内存
- **MPE** (Multi-Processing Extension)：多处理器

**支持的架构-平台组合**：
- `riscv32e-npc`：RISC-V 32E + NPC
- `riscv32e-ysyxsoc`：RISC-V 32E + ysyxSoC
- `riscv32e-nemu`：RISC-V 32E + NEMU
- `native`：Linux 原生

### ysyxSoC/ - SoC 集成框架

基于 Chisel/Scala 构建的 SoC 顶层与互联架构。

```
ysyxSoC/
├── src/               # Chisel 源码
│   ├── SoC.scala     # SoC 核心
│   ├── CPU.scala     # CPU 封装 (BlackBox)
│   ├── device/       # 外设封装
│   └── amba/         # AXI4/APB 桥接
├── perip/            # 外设 Verilog 实现
├── rocket-chip/      # Rocket Chip 依赖
└── Makefile
```

**内存映射**：

| 外设 | 地址范围 | 总线 |
|------|---------|------|
| SRAM | 0x0f000000 | AXI4 |
| UART | 0x10000000 | APB |
| SPI  | 0x10001000 | APB |
| GPIO | 0x10002000 | APB |
| Keyboard | 0x10011000 | APB |
| MROM | 0x20000000 | AXI4 |
| VGA  | 0x21000000 | APB |
| Flash (XIP) | 0x30000000 | APB |
| PSRAM | 0x80000000 | APB |
| SDRAM | 0xa0000000 | AXI4 |

**生成 Verilog**：
```bash
cd ysyxSoC
make verilog
```

### nvboard/ - 虚拟 FPGA 板卡

基于 SDL2 的可视化硬件模拟库，模拟 FPGA 开发板的外设。

```
nvboard/
├── include/          # 头文件
├── src/              # 源码实现
│   ├── vga.cpp      # VGA 显示
│   ├── keyboard.cpp # 键盘输入
│   ├── led.cpp      # LED 指示灯
│   └── segs7.cpp    # 七段数码管
├── scripts/          # 构建脚本
└── example/          # 示例项目
```

**支持的外设**：
- VGA 显示 (640x480)
- PS/2 键盘
- LED 指示灯
- 七段数码管
- 拨码开关
- 按钮

### am-kernels/ - 测试程序集

基于 AM 运行的各种测试和示例程序。

```
am-kernels/
├── tests/
│   ├── cpu-tests/    # CPU 指令测试 (add, shift, mul 等)
│   ├── am-tests/     # AM 功能测试 (video, keyboard 等)
│   └── psram-test/   # PSRAM 测试
├── benchmarks/
│   ├── coremark/     # CoreMark 性能测试
│   ├── dhrystone/    # Dhrystone 性能测试
│   └── microbench/   # 微基准测试
└── kernels/
    ├── hello/        # Hello World
    ├── typing-game/  # 打字游戏
    ├── snake/        # 贪吃蛇
    └── litenes/      # NES 模拟器
```

**运行测试**：
```bash
cd am-kernels/tests/cpu-tests

# 在 NEMU 上运行
make ARCH=riscv32e-nemu ALL=add run

# 在 ysyxSoC 上运行
make ARCH=riscv32e-ysyxsoc ALL=add run

# 运行所有测试
make ARCH=riscv32e-ysyxsoc run
```

### fceux-am/ - FC 模拟器

移植到 AM 平台的红白机 (NES/FC) 模拟器，可以运行《超级玛丽》等游戏。

```bash
cd fceux-am
make ARCH=riscv32e-ysyxsoc run
```

### rt-thread-am/ - RT-Thread 移植

RT-Thread 实时操作系统在 AM 平台的移植版本。

```
rt-thread-am/
├── bsp/abstract-machine/  # AM 板级支持包
├── src/                   # RT-Thread 内核
├── components/            # 组件 (文件系统, Shell 等)
└── tools/                 # 构建工具
```

## 构建与运行

### NPC 独立仿真

```bash
cd npc
make run IMG=/path/to/program.bin
make wave  # 生成并查看波形
```

### NPC + ysyxSoC

```bash
cd npc

# 编译并运行
make -f Makefile.soc run IMG=/path/to/program.bin

# 启用 NVBoard 可视化
make -f Makefile.soc nvboard IMG=/path/to/program.bin

# 使用流水线版本
make -f Makefile.soc pipeline IMG=/path/to/program.bin
```

### am-kernels 测试

```bash
cd am-kernels/tests/cpu-tests

# 指定测试用例
make ARCH=riscv32e-ysyxsoc ALL=add run

# 运行 benchmark
cd am-kernels/benchmarks/coremark
make ARCH=riscv32e-ysyxsoc run
```

## 项目结构

```
.
├── abstract-machine/   # 硬件抽象层
├── am-kernels/         # 测试程序集
├── fceux-am/           # FC 模拟器
├── nemu/               # NEMU 参考模型
├── npc/                # 处理器核心
├── nvboard/            # 虚拟 FPGA 板卡
├── rt-thread-am/       # RT-Thread 移植
├── ysyxSoC/            # SoC 框架
├── init.sh             # 环境初始化脚本
├── Makefile            # 顶层 Makefile
└── README.md           # 本文件
```

## 许可证

本项目各模块遵循其原有的开源许可证。

## 参考资料

- [一生一芯项目](https://ysyx.oscc.cc/)
- [RISC-V 规范](https://riscv.org/technical/specifications/)
- [Verilator 文档](https://verilator.org/guide/latest/)
