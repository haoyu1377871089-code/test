# NPC 流水线处理器项目进展报告

> 更新日期：2026-01-28

## 一、项目概述

将当前 RV32E 多周期 NPC 处理器改造为五级流水线处理器，处理各种冒险，并通过转发等技术优化性能。

### 当前架构状态

| 项目 | 当前状态 |
|------|----------|
| 指令集 | RV32E |
| 处理器架构 | 五级流水线（已完成） |
| I-Cache | 4KB, 2-way, 16B line, 99.67% hit rate |
| D-Cache | 已实现，可选启用 |
| 总线协议 | AXI4 Burst |
| 当前 CPI | 49.70（流水线版本） |

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

### 🎉 重要里程碑 (2026-01-28)

**✅ microbench 测试全部通过！**
- 所有 10 个 benchmark 均通过 (qsort, queen, bf, fib, sieve, 15pz, dinic, lzip, ssort, md5)
- 流水线 CPI: 49.70 (相比多周期版本 55.66，**提升 10.7%**)
- 关键修复: JALR 指令返回地址计算错误 (commit ec9f9f5)

---

## 三、已完成工作

### 3.1 阶段1：模块拆分（已完成）

将单体 `EXU.v` 拆分为独立模块：

| 模块 | 职责 |
|------|------|
| `IDU.v` | 指令译码：opcode/funct3/funct7 解码、立即数生成 |
| `EXU.v` | 执行计算：ALU 运算、分支条件判断、地址计算 |
| `LSU.v` | 访存控制：load/store 请求生成、数据对齐 |
| `WBU.v` | 写回：寄存器写入、CSR 更新 |

文件位置：`npc/vsrc/ysyxsoc/pipeline/`

### 3.2 I-Cache 优化（已完成）

| 优化项 | 效果 |
|--------|------|
| 启用 I-Cache | CPI 从 951 降至 55（17x 提升） |
| 16B Cache Line + AXI4 Burst | Miss 减少 73.3%，Hit Rate 99.67% |

---

## 四、当前工作：阶段2 流水线连接

### 4.1 已实现内容

- 五级流水线框架：IF → ID → EX → MEM → WB
- 流水段寄存器：`IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB`
- 握手信号：`valid/ready` 控制流水线推进
- Flush 信号传递：支持分支/跳转时冲刷流水线
- RAW 冒险检测：检测 EX/MEM/WB 阶段的数据依赖
- 流水线阻塞：RAW 冒险时暂停 IF/ID 阶段，插入气泡
- 控制冒险冲刷：分支/跳转时冲刷 IF/ID 阶段（待修复）

### 4.2 调试进展 (2026-01-28 更新)

**原问题**：流水线版本在 `dummy` 测试中运行异常缓慢，PC 停留在 `0x30000144`。

**已修复问题 #1：RAW 冒险气泡插入逻辑错误**

- **原因**：当检测到 RAW 冒险时，`stall_id=1`，但 ID/EX 寄存器保持原值而不是插入气泡
- **后果**：ID 阶段指令被重复执行或使用错误数据
- **修复**：`stall_id=1` 时设置 `id_ex_valid <= 0`

**已修复问题 #2：MEM/WB valid 信号错误清零**

- **原因**：MEM/WB 更新逻辑的错误 else 分支在 `lsu_out_valid=0` 时将 `mem_wb_valid` 清零
- **后果**：RAW 冒险检测提前解除，指令读取未更新的寄存器值
- **修复**：删除错误的 else 分支

**已修复问题 #3：WBU 写回时序与 RAW 检测不同步**

- **原因**：RAW 检测使用 `mem_wb_valid`，但 WBU 接收数据后需额外周期才写入寄存器堆
- **后果**：WBU 写入时 `mem_wb_valid` 已清零，`addi sp, sp, -4` 读取 `sp=0`
- **修复**：RAW 检测改用 WBU 的写入信号（`wbu_rf_wen`, `wbu_rf_waddr`）

```verilog
// RAW 冒险检测使用 WBU 写入信号
wire wb_writes_reg = wbu_rf_wen && (wbu_rf_waddr != 5'b0);
wire pending_wb_writes = mem_wb_valid && mem_wb_reg_wen && (pending_wb_rd != 5'b0);
wire raw_wb_rs1 = id_uses_rs1 && ((wb_writes_reg && (id_rs1 == wbu_rf_waddr)) || 
                                  (pending_wb_writes && (id_rs1 == pending_wb_rd)));
```

**当前状态**：
- `addi sp, sp, -4` 得到正确结果（`0x0f002000`）
- 程序能继续执行，进入 `uart_init`
- 但陷入 `uart_init` 的延迟循环

### 4.3 新发现问题 (2026-01-28 深入调试)

**问题 #4：分支指令重复提交**

从调试日志发现 branch 指令被提交两次：
```
[COMMIT@17947] pc=3000016c inst=fef758e3 ...
[COMMIT@17949] pc=3000016c inst=fef758e3 ...
```

**问题 #5：store 指令被跳过**

`uart_init` 延迟循环代码：
```asm
3000015c:  lw   a5, 0(sp)      # load i
30000160:  addi a5, a5, 1      # i++
30000164:  sw   a5, 0(sp)      # store i  <-- 被跳过！
30000168:  lw   a5, 0(sp)      # load i   <-- 被跳过！
3000016c:  bge  a4, a5, ...    # branch
```

实际执行：`lw → addi → branch`（跳过了 sw 和第二个 lw）

**根因分析**：

1. **LSU out_valid 持续问题**：当不需要访存的指令（如 branch）通过 LSU 时，`out_valid=1` 在 WBU 忙时不会清零
2. **重复握手**：WBU 完成后回到 IDLE，又看到 `mem_wb_valid=1`，再次锁存同样数据
3. **flush 时序问题**：branch 在 EX 阶段触发 flush，但已在流水线中的 sw/lw 被错误冲刷

**已尝试修复**：

修改 `LSU_pipeline.v` 的 `out_valid` 清零逻辑，确保每条指令只输出一个周期的 valid：
```verilog
// S_IDLE 状态
if (out_valid && !in_valid) begin
    out_valid <= 1'b0;  // 无新输入时清零
end else if (in_valid && in_ready) begin
    // ... 正常处理
end else if (out_valid && out_ready) begin
    out_valid <= 1'b0;  // 数据被消费
end
```

### 4.4 待解决问题

1. **store/load 指令被跳过**
   - 需检查 flush 信号是否错误地冲刷了 MEM 阶段的指令
   - 检查 EX/MEM 寄存器在 flush 时的处理

2. **分支重复提交**
   - MEM/WB 的 valid 信号清零时序需要与 LSU out_valid 协调
   - 可能需要在 MEM/WB 层级增加握手确认机制

---

## 五、后续步骤需求

### 5.1 阶段2 完成需求（当前优先）

| 需求 | 说明 |
|------|------|
| 修复 Flash AXI 响应问题 | 确保 ICache 能正确从 Flash 获取指令 |
| 通过 `dummy` 测试 | 无冒险程序正确执行 |
| 验证流水线并行性 | 观察波形确认多阶段同时执行 |

### 5.2 阶段3：RAW 阻塞

| 需求 | 说明 |
|------|------|
| RAW 冒险检测 | 在 IDU 中检测 EX/MEM/WB 阶段的数据依赖 |
| 阻塞逻辑 | 检测到冒险时暂停 IF/ID 阶段 |
| 测试用例 | 编写/验证有数据依赖的测试程序 |
| 性能计数器 | 添加 `perf_stall_raw` 统计阻塞周期 |

### 5.3 阶段4：转发技术

| 需求 | 说明 |
|------|------|
| 转发路径 | EXU→IDU, LSU→IDU, WBU→IDU |
| 转发优先级 | 最年轻优先（EX > MEM > WB） |
| load-use 阻塞 | load 指令后紧跟使用结果的指令需阻塞 |
| 性能验证 | 对比阻塞周期减少量 |

### 5.4 阶段5：控制冒险

| 需求 | 说明 |
|------|------|
| 分支预测 | 静态预测：总是预测不跳转 |
| 流水线冲刷 | 预测错误时冲刷 IF/ID 阶段 |
| 跳转处理 | JAL/JALR 立即冲刷 |
| 性能计数器 | 添加 `perf_flush_branch` |

### 5.5 阶段6：异常处理

| 需求 | 说明 |
|------|------|
| 精确异常 | PC 随流水线传递，异常仅在 WBU 处理 |
| ecall/mret | 正确更新 mepc/mcause，跳转到 mtvec |
| fence.i | 冲刷年轻指令，可选 I-Cache invalidate |

---

## 六、性能目标

| 指标 | 多周期（当前） | 流水线（预期） |
|------|----------------|----------------|
| CPI | ~56 | ~20-30 |
| EXEC 占比 | 5% | 提升 |
| WAIT_LSU 占比 | 64% | 略降（仍是瓶颈） |

**注意**：由于 LSU 延迟（load 181 cycles, store 117 cycles）远大于流水线深度，流水线的主要收益来自计算指令的并行执行。

---

## 七、关键文件

| 文件路径 | 说明 |
|----------|------|
| `npc/vsrc/ysyxsoc/pipeline/NPC_pipeline.v` | 流水线顶层模块 |
| `npc/vsrc/ysyxsoc/pipeline/ysyx_pipeline_top.v` | SoC 集成顶层 |
| `npc/vsrc/ysyxsoc/ICache.v` | 指令缓存 |
| `npc/vsrc/ysyxsoc/IFU_AXI4.v` | IFU AXI4 Master |
| `npc/vsrc/ysyxsoc/AXI4_Arbiter.v` | AXI4 仲裁器 |
| `npc/Makefile.soc` | 构建配置 |

---

## 八、测试命令

```bash
# 构建并运行流水线版本
cd /home/hy258/ysyx-workbench/npc
make -f Makefile.soc pipeline

# 运行 dummy 测试（带超时）
timeout 120s ./build_soc/ysyxSoCFull --no-nvboard -b \
  /home/hy258/ysyx-workbench/am-kernels/tests/cpu-tests/build/dummy-riscv32e-ysyxsoc.bin

# 运行单周期版本对比
make -f Makefile.soc soc
timeout 120s ./build_soc/ysyxSoCFull --no-nvboard -b \
  /home/hy258/ysyx-workbench/am-kernels/tests/cpu-tests/build/dummy-riscv32e-ysyxsoc.bin
```
