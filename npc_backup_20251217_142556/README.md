# NPC 仿真程序重构说明

本次重构目标：将 `/home/hy258/ysyx-workbench/npc/csrc` 目录拆分为更清晰的模块化 `.cpp` 文件，移除无用或过于繁琐的指令，提升可读性与维护性；并在不影响功能的前提下，完成回归验证。

## 目录结构

- `csrc/main.cpp`：程序入口，负责初始化 Verilator、加载镜像、复位、主循环与退出状态打印。
- `csrc/sim.h`：公共接口声明，包含指令映射、程序加载和仿真循环相关函数原型。
- `csrc/program.cpp`：程序加载与指令映射。实现二进制读取、构建 PC→指令表、调用 DPI 将镜像写入 NPC 内存。
- `csrc/loop.cpp`：核心仿真循环。封装首条指令执行与单周期处理，移除冗余调试输出，仅保留关键状态更新与波形转储。

> 说明：原 `main.cpp` 中的 DiffTest 相关代码与重复函数定义已移除，保留与 NPC 仿真直接相关的逻辑。

## 构建与运行

- 依赖：已在 `init.sh` 中配置好 `AM_HOME`、`NPC_HOME`、`NVBOARD_HOME` 等环境变量；RISC-V 交叉编译器为 `riscv64-linux-gnu-`。
- 构建与运行 hello 测试：

```bash
make -C /home/hy258/ysyx-workbench/am-kernels/tests/am-tests run ARCH=riscv32e-npc mainargs=h
```

- 运行结果示例：

```
加载程序文件: /home/hy258/ysyx-workbench/am-kernels/tests/am-tests/build/amtest-riscv32e-npc.bin
内存初始化成功: [0x80000000, 0x87ffffff], 大小: 128 MB
成功加载文件 ... 大小 614596 字节
开始程序仿真...
666
(共10次)
仿真完成: 检测到ebreak指令
HIT GOOD TRAP at pc = 0x800010a8
```

## 关键改动

- 移除了 DiffTest 动态库加载、寄存器比对与相关的详细打印，消除多余依赖与复杂性。
- 将读取镜像与指令映射逻辑集中到 `program.cpp`，统一维护 PC→指令表，避免 `main.cpp` 中重复实现。
- 将仿真时钟与指令有效信号处理封装到 `loop.cpp`，主流程清晰：`execute_first_instruction()` → 循环 `process_one_cycle()` → 根据 `end_flag`/`ebreak` 退出。
- 统一波形生成位置与文件名（`build/dump.vcd`），便于调试。

## 使用建议

- 若需开启更详细的调试，请在 `loop.cpp` 中适当恢复指令打印与寄存器状态输出，建议通过宏或开关控制。
- 若需支持 DiffTest，请在新模块基础上新增一个 `difftest.cpp`，与 NEMU 或参考模型对接，避免将复杂逻辑混入 `main.cpp`。
- 若后续扩充外设或内存模型，建议继续保持模块化：将内存、外设总线、设备仿真分别置于独立源文件。

## 维护说明

- 当前重构保证 `am-tests` 的 `hello` 用例在 `riscv32e-npc` 架构上能够成功运行并命中 GOOD TRAP。
- 当添加新指令或修改 NPC 顶层接口时，请同步更新 `sim.h` 的函数声明与 `program.cpp`/`loop.cpp` 的实现。

如需进一步定制或增强日志与测试能力，我可以继续协助完善。