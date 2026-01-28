# NPC 流水线处理器项目进展报告

> 更新日期：2026-01-28 (最新)

## 一、项目概述

将当前 RV32E 多周期 NPC 处理器改造为五级流水线处理器，处理各种冒险，并通过转发等技术优化性能。

### 当前架构状态

| 项目 | 当前状态 |
|------|----------|
| 指令集 | RV32E |
| 处理器架构 | 多周期 + 五级流水线（功能基本完成） |
| I-Cache | 4KB, 2-way, 16B line, 99.67% hit rate |
| D-Cache | 已实现，可选启用 |
| 总线协议 | AXI4 Burst |
| 多周期 CPI | ~56 (基准) |
| 流水线 CPI | ~36-42 (约 14% 提升) |

---

## 二、任务阶段进展

| 阶段 | 任务内容 | 状态 |
|------|----------|------|
| 阶段1 | 拆分模块 + 串行执行验证（无流水线，仍为多周期） | ✅ 已完成 |
| 阶段2 | 实现流水线连接 + 简单测试（无 RAW 依赖的程序） | ✅ 已完成 |
| 阶段3 | 实现 RAW 阻塞 + 带依赖的测试用例 | ✅ 已完成 |
| 阶段4 | 实现转发技术 + 验证性能提升 | ✅ 已完成 |
| 阶段5 | 实现控制冒险处理 + 分支/跳转测试 | ✅ 已完成 |
| 阶段6 | 实现异常和 fence.i + 完整测试 | ✅ 已完成 |
| 阶段7 | 通过 microbench 完整测试 | ⚠️ 部分完成 |

---

## 三、性能数据 (2026-01-28)

### 3.1 CPU 测试 CPI 对比

| 测试程序 | 多周期 CPI | 流水线 CPI | 性能提升 |
|----------|-----------|------------|----------|
| dummy | 42.57 | 36.22 | 14.9% |
| add | 45.71 | 39.34 | 13.9% |
| fib | 46.14 | 39.75 | 13.9% |
| quick-sort | 47.86 | 41.50 | 13.3% |
| load-store | 46.52 | 40.12 | 13.8% |
| string | 57.59 | 50.94 | 11.5% |
| bit | 44.85 | 38.48 | 14.2% |
| bubble-sort | 49.03 | 42.66 | 13.0% |
| shift | 44.93 | 38.56 | 14.2% |
| goldbach | 36.02 | 29.99 | 16.7% |

**平均性能提升：约 14%**

### 3.2 测试通过情况

| 测试 | 状态 | 备注 |
|------|------|------|
| dummy | ✅ PASS | |
| add | ✅ PASS | |
| bit | ✅ PASS | |
| bubble-sort | ✅ PASS | |
| shift | ✅ PASS | |
| hello | ✅ PASS | |
| hello-str | ✅ PASS | |
| load-store | ✅ PASS | 字节/半字访存 |
| min3 | ✅ PASS | |
| fact | ✅ PASS | |
| fib | ✅ PASS | |
| goldbach | ✅ PASS | |
| quick-sort | ✅ PASS | |
| string | ✅ PASS | 字符串操作 |
| recursion | ⚠️ TIMEOUT | 深度递归超时 |
| microbench | ⚠️ FAIL | 堆断言失败 |

---

## 四、已修复的关键 Bug

### 4.1 exit_code 传递问题

**问题**：WBU 硬编码 `exit_code = 0`，导致无法获取程序真实返回值。

**解决方案**：
1. RegisterFile 添加第三个读端口，用于读取 a0 (x10)
2. IDU 输出 `out_a0_data` 信号
3. 通过 ID/EX、EX/MEM、MEM/WB 级间寄存器传递 a0 值
4. WBU 使用传递的 a0 值作为 `exit_code`

### 4.2 a0 寄存器转发问题

**问题**：`halt()` 函数中 `addi a0` 紧接着 `ebreak`，译码时 `addi` 可能还在流水线后续阶段。

**解决方案**：为 a0 添加转发逻辑，与 rs1/rs2 转发类似。

### 4.3 LSU 字节/半字加载对齐问题

**问题**：LSU_AXI4 已经对返回数据进行了字节对齐，但 LSU_pipeline 又进行了一次对齐，导致双重对齐错误。

**解决方案**：移除 LSU_pipeline 中的字节选择逻辑，仅保留符号/零扩展。

```verilog
// 修复前：根据 addr_offset 选择字节（错误）
case (addr_offset)
    2'b00: load_byte = mem_result[7:0];
    2'b01: load_byte = mem_result[15:8];
    ...
endcase

// 修复后：直接使用低位（LSU_AXI4 已对齐）
case (funct3_reg)
    3'b000: load_result = {{24{mem_result[7]}}, mem_result[7:0]};  // LB
    3'b001: load_result = {{16{mem_result[15]}}, mem_result[15:0]}; // LH
    ...
endcase
```

---

## 五、流水线架构设计

### 5.1 五级流水线结构

```
IF → ID → EX → MEM → WB
     ↑__________|_______|  (转发路径)
     |_____________|       (阻塞信号)
```

### 5.2 冒险处理

| 冒险类型 | 处理方式 |
|----------|----------|
| RAW 数据冒险 | 转发 (EX→ID, MEM→ID, WB→ID) |
| Load-use 冒险 | 阻塞一个周期 |
| 控制冒险 | 冲刷 IF/ID 阶段 |
| 结构冒险 | MEM 访存时阻塞 |

### 5.3 关键模块

| 模块 | 职责 |
|------|------|
| `NPC_pipeline.v` | 流水线顶层，级间寄存器管理 |
| `IDU.v` | 指令译码、寄存器读取 |
| `EXU_pipeline.v` | ALU 运算、分支计算 |
| `LSU_pipeline.v` | 访存控制、数据对齐 |
| `WBU.v` | 寄存器写回、异常处理 |

---

## 六、待解决问题

### 6.1 microbench 堆断言失败

**现象**：`[qsort] Quick sort: Assertion fail at bench.c:165`

**分析**：
- 断言检查 `hbrk - heap.start <= setting->mlim` (1KB)
- 多周期版本通过，流水线版本失败
- 可能是全局变量访问或结构体成员访问的流水线特有问题

**状态**：待继续调查

### 6.2 recursion 测试超时

**现象**：测试运行超过 180 秒仍未完成

**分析**：
- 深度递归可能触发特定的流水线边界条件
- 可能与栈操作频繁导致的冒险处理有关

**状态**：待继续调查

---

## 七、构建和测试命令

```bash
# 构建多周期版本
cd /workspace/npc
make -f Makefile.soc soc

# 构建流水线版本
make -f Makefile.soc pipeline

# 运行 CPU 测试
./build_soc/ysyxSoCFull --no-gui ../am-kernels/tests/cpu-tests/build/dummy-riscv32e-ysyxsoc.bin

# 运行 microbench
./build_soc/ysyxSoCFull --no-gui ../am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin
```

---

## 八、关键文件

| 文件路径 | 说明 |
|----------|------|
| `npc/vsrc/ysyxsoc/pipeline/NPC_pipeline.v` | 流水线顶层模块 |
| `npc/vsrc/ysyxsoc/pipeline/IDU.v` | 指令译码单元 |
| `npc/vsrc/ysyxsoc/pipeline/EXU_pipeline.v` | 执行单元 |
| `npc/vsrc/ysyxsoc/pipeline/LSU_pipeline.v` | 访存单元 |
| `npc/vsrc/ysyxsoc/pipeline/WBU.v` | 写回单元 |
| `npc/vsrc/ysyxsoc/RegisterFile.v` | 寄存器文件 |
| `npc/Makefile.soc` | 构建配置 |
