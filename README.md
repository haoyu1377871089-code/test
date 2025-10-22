# ysyx-workbench 使用手册

本仓库为 ysyx 学习与实验工作台，集成以下子项目：
- `abstract-machine`：抽象机和通用库
- `am-kernels`：AM 上的测试与内核示例
- `nemu`：教学用模拟器（含 RISC-V 等 ISA）
- `npc`：自主 CPU（Verilog + Verilator 仿真）
- `nvboard`：可视化外设与板卡模拟（含示例）
- `fceux-am`：FCEUX 在 AM 平台的移植
- `trae_docs`：项目说明与文档

## 环境准备
请在 Linux 环境下使用，建议 Ubuntu 20.04+/22.04+。
需要安装：
- 基础工具：`git`、`make`、`gcc`/`g++`、`python3`
- Verilog 仿真：`verilator`
- 图形/多媒体库：`libsdl2-dev`（部分 NVBoard/FCEUX-AM 场景可能需要）

示例安装（Ubuntu）：
```
sudo apt update
sudo apt install -y git make gcc g++ python3 verilator libsdl2-dev
```

## 初始化
执行根目录初始化脚本（可选）：
```
bash init.sh
```
该脚本用于准备部分依赖或环境变量（如无特殊需求，可跳过）。

## 快速上手
以下为常用子项目的构建与运行示例，具体命令以各目录内 README/Makefile 为准。

### 1) 在 NEMU 上运行 AM 测试
进入 AM 测试目录并选择 RISC-V NEMU 作为运行平台：
```
cd am-kernels/tests/am-tests
make ARCH=riscv32-nemu run
```
- 运行后进入 NEMU 监控器，常用命令：`c` 继续、`q` 退出。
- 可通过 `mainargs=<arg>` 为程序传参，例如：
```
make ARCH=riscv32-nemu mainargs=y run
```

### 2) 构建与运行 NEMU
```
cd nemu
make -j
# 构建完成后，可结合 am-kernels 的 run 目标运行程序
```
NEMU 使用 Kconfig/Makefile 构建体系，更多细节参考 `nemu/README.md`。

### 3) 构建与运行 NPC（Verilator 仿真）
```
cd npc
make -j
# 生成可执行位于 build/ 目录（如 build/top），不同工程可能提供 run 目标
```
建议先阅读 `npc/README.md` 与 `npc/Makefile` 了解工程入口与仿真参数。

### 4) 体验 NVBoard 示例
```
cd nvboard/example
make -j
# 如有提供 run 目标：
make run
```
NVBoard 用于按键/拨码/LED/VGA 等外设的可视化交互，更多使用方法见 `nvboard/README.md`。

### 5) 构建 fceux-am
```
cd fceux-am
make -j
```
该项目在 AM 平台上运行 FCEUX 内核，依赖在目录内的资源与源代码，具体功能与运行方式请参考 `fceux-am/README.md`。

## 目录结构速览
- `abstract-machine/` 抽象机与通用库
- `am-kernels/` AM 上的测试与内核示例
- `nemu/` 教学模拟器
- `npc/` 自研 CPU 工程
- `nvboard/` 可视化板卡/外设模拟（含示例）
- `fceux-am/` FCEUX-AM 工程
- `trae_docs/` 文档与说明

## 常见问题
- 若遇到三方库缺失，请安装相应开发包（如 `libsdl2-dev`）。
- 若 `make` 报错，请先清理再重试：`make clean` 或删除 `build/` 后重新构建。
- 本仓库已将 `am-kernels`、`fceux-am`、`nvboard` 作为普通目录管理，非子模块。若需要以子模块管理，请按需在独立仓库中创建并使用 `git submodule add`。

## 开发流程
- 提交改动：
```
git add .
git commit -m "<描述你的改动>"
git push
```
- 分支协作：默认分支为 `main`，如需创建特性分支：`git checkout -b feature/<name>`。

## 许可证
各子项目目录内附带相应 LICENSE，请按其条款使用。