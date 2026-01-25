## 1. 项目概览

本项目旨在提供一个完整的软硬件协同设计环境，主要包含以下核心组件：
- **NPC (New Processor Core)**: 基于 Verilog/Chisel 设计的 RISC-V 处理器核心。
- **NEMU (NJU Emulator)**: 作为参考模型（Ref Model）的教学用 RISC-V 模拟器。
- **Abstract Machine (AM)**: 裸机编程的硬件抽象层，实现 "Write Once, Run Anywhere"。
- **ysyxSoC**: 基于 Chisel/Scala 的 SoC 集成框架，包含总线与外设集成。
- **NVBoard**: 虚拟 FPGA 开发板，提供 VGA、键盘、开关等外设的可视化模拟。

## 2. 目录结构详解

| 目录名 | 详细说明 |
| :--- | :--- |
| **`abstract-machine/`** | **抽象机 (Abstract Machine)**<br>屏蔽了底层硬件细节的软件开发层。包含：<br>- `klib`: 通用 C 库 (string, stdio 等)。<br>- `am`: 架构相关的运行时实现 (trm, ioe 等)。<br>- `scripts`: 编译构建脚本，定义了不同架构的编译选项。 |
| **`am-kernels/`** | **AM 程序集**<br>基于 AM 运行的各种软件程序。<br>- `tests/cpu-tests`: 基础 CPU 指令测试 (add, shift 等)。<br>- `tests/am-tests`: AM 功能测试 (video, keyboard 等)。<br>- `benchmarks`: 性能测试基准 (coremark, dhrystone)。 |
| **`nemu/`** | **NEMU 模拟器**<br>教学用的高性能 RISC-V 解释器。通常作为“黄金模型 (Ref Model)”与 NPC 进行 DiffTest (差分测试)，用于验证 NPC 的正确性。支持通过 Kconfig 进行功能剪裁。 |
| **`npc/`** | **处理器设计 (New Processor Core)**<br>你自己的 CPU 设计目录。<br>- `vsrc/`: Verilog/SystemVerilog 源码。<br>- `csrc/`: C++ 仿真顶层，基于 Verilator 构建仿真环境。<br>- `build/`: 编译产物，包含波形文件 `dump.vcd`。 |
| **`nvboard/`** | **虚拟板卡 (NVBoard)**<br>基于 SDL2 的可视化硬件模拟库。它模拟了 FPGA 开发板上的 LED、数码管、拨码开关、VGA 接口等，让你在没有实物板卡的情况下也能看到硬件效果。 |
| **`ysyxSoC/`** | **SoC 集成**<br>基于 Chisel/Scala 构建的 SoC 顶层与互联架构。包含 AXI4 总线、Crossbar、UART/SPI 控制器等。这是将 NPC 接入真实总线环境的地方。 |
| **`fceux-am/`** | **FC 模拟器**<br>移植到 AM 平台的红白机 (NES) 模拟器。可以编译运行在 NEMU 或你的 NPC 上，用来玩《超级玛丽》等游戏。 |


## 3.测试要求
请在am-kernels内选择合适的文件，以make ARCH=riscv32e-ysyxsoc mainargs=（按照你的需要填写）run的格式运行
