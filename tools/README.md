# 工具链安装说明

本目录包含项目所需的工具链：

## RISC-V 工具链

- **位置**: `/workspace/tools/riscv64-unknown-elf`
- **版本**: SiFive GCC 8.3.0-2020.04.1
- **主要工具**:
  - `riscv64-unknown-elf-gcc` - C/C++ 编译器
  - `riscv64-unknown-elf-objcopy` - 目标文件转换工具
  - `riscv64-unknown-elf-objdump` - 反汇编工具
  - 其他 RISC-V 工具链工具

## Mill 构建工具

- **位置**: `/workspace/tools/mill`
- **版本**: 0.11.5
- **用途**: Scala/Chisel 项目的构建工具

## 环境变量配置

环境变量已自动添加到 `~/.bashrc`：

```bash
# RISC-V Toolchain
export RISCV_TOOLCHAIN=/workspace/tools/riscv64-unknown-elf
export PATH=$RISCV_TOOLCHAIN/bin:$PATH

# Mill Build Tool
export MILL_HOME=/workspace/tools
export PATH=$MILL_HOME:$PATH
```

## 使用方法

### 使用 RISC-V 工具链

```bash
# 编译 C 程序
riscv64-unknown-elf-gcc -o hello hello.c

# 查看版本
riscv64-unknown-elf-gcc --version
```

### 使用 Mill

```bash
# 查看版本
mill --version

# 在 ysyxSoC 项目中使用
cd ysyxSoC/rocket-chip
mill emulator[freechips.rocketchip.system.TestHarness,freechips.rocketchip.system.DefaultConfig].elf
```

## 验证安装

运行以下命令验证工具链是否正常工作：

```bash
riscv64-unknown-elf-gcc --version
mill --version
```

## 注意事项

- 如果环境变量未生效，请运行 `source ~/.bashrc` 或重新打开终端
- RISC-V 工具链路径也可以通过 `RISCV` 环境变量设置（某些项目使用此变量）
- Mill 需要 Java 运行时环境（JRE），当前系统已安装 Java 21
