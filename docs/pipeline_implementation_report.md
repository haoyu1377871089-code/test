# 流水线实现报告

## 概述

本报告记录了五级流水线处理器的实现过程、遇到的问题及解决方案，以及最终的性能测试结果。

## 实现的流水线结构

### 五级流水线阶段

1. **IF (Instruction Fetch)** - 取指阶段
   - 使用 I-Cache 加速指令获取
   - 支持指令预取和缓存刷新

2. **ID (Instruction Decode)** - 译码阶段
   - 指令译码和寄存器读取
   - 数据转发目标

3. **EX (Execute)** - 执行阶段
   - ALU 运算
   - 分支条件判断和目标地址计算
   - CSR 读取

4. **MEM (Memory Access)** - 访存阶段
   - Load/Store 操作
   - 使用 LSU_AXI4 接口访问内存

5. **WB (Write Back)** - 写回阶段
   - 寄存器写回
   - CSR 写回

### 冒险处理机制

#### 数据冒险 (Data Hazards)

1. **数据转发 (Forwarding)**
   - EX → ID: ALU 结果直接转发
   - MEM → ID: Load 数据转发（当 LSU 输出有效时）
   - WB → ID: 写回数据转发

2. **Load-Use 冒险处理**
   - 当 EX 阶段是 Load 指令，且后续指令依赖其结果时，插入一个 stall
   - MEM 阶段 Load 等待数据返回时，保持 ID 阶段 stall

#### 控制冒险 (Control Hazards)

1. **分支/跳转处理**
   - 分支在 EX 阶段解析
   - 分支成功时冲刷 IF 和 ID 阶段

2. **fence.i 处理**
   - 冲刷整个流水线和 I-Cache

## 关键 Bug 修复

### 1. JALR 指令返回地址错误

**问题描述：**
JALR 指令将跳转目标地址 `(rs1 + imm) & ~1` 存入目标寄存器，而不是返回地址 `PC + 4`。

**症状：**
- 函数调用后返回到错误的地址
- microbench 中 `bench_alloc` 被重复调用多次

**解决方案：**
```verilog
// 修复前：JALR 的 alu_result 是跳转目标
7'b1100111: alu_result = (alu_a + alu_b) & 32'hFFFFFFFE;

// 修复后：JALR 的 alu_result 是返回地址
7'b1100111: alu_result = in_pc + 32'd4;

// 跳转目标单独计算
wire [31:0] jalr_target = (in_rs1_data + in_imm) & 32'hFFFFFFFE;
```

### 2. LSU 数据锁存问题

**问题描述：**
`load_result` 使用 `mem_rdata` 而不是锁存的 `mem_result`，当状态机进入 `S_DONE` 状态时，`mem_rdata` 可能已经改变。

**解决方案：**
使用锁存的 `mem_result` 进行 load 数据提取：
```verilog
3'b000: load_result = {{24{mem_result[7]}}, mem_result[7:0]};   // LB
3'b001: load_result = {{16{mem_result[15]}}, mem_result[15:0]}; // LH
// ...
```

### 3. MEM 阶段转发条件

**问题描述：**
`mem_can_forward` 没有检查 `ex_mem_valid`，可能使用过期的 `ex_mem_rd` 进行转发。

**解决方案：**
```verilog
wire mem_can_forward = ex_mem_valid && lsu_out_valid && ex_mem_reg_wen && (mem_rd != 5'b0);
```

## 性能测试结果

### microbench 测试 (test 设置)

| 指标 | 单周期版本 | 流水线版本 | 改进 |
|------|-----------|-----------|------|
| Total Cycles | 30,593,144 | 27,474,092 | **-10.2%** |
| Retired Instructions | 549,606 | 550,137 | +0.1% |
| CPI | 55.66 | 49.94 | **-10.3%** |
| Scored Time | 10.000 ms | 10.000 ms | - |
| Total Time | 21.000 ms | 21.000 ms | - |

### CPU 测试结果

所有 17 个 CPU 测试全部通过：
- dummy, add, sum, fib
- mul-longlong, add-longlong, sub-longlong
- load-store, quick-sort, bubble-sort
- string, recursion, crc32
- goldbach, pascal, mersenne
- load-chain (新增测试)

## 性能分析

1. **CPI 改进来源：**
   - 数据转发减少了 Load-Use 的 stall 周期
   - 流水线允许多条指令同时在不同阶段执行

2. **CPI 仍然较高的原因：**
   - 访存延迟很高（平均 Load 延迟 185 cycles，Store 延迟 107 cycles）
   - I-Cache miss 时的 refill 延迟（约 2975 cycles）
   - 大量时间花费在等待 LSU（单周期版本约 65%）

3. **潜在优化方向：**
   - 实现 D-Cache 减少访存延迟
   - 分支预测减少控制冒险的 flush 开销
   - 增加 I-Cache 大小减少 miss rate

## 结论

五级流水线成功实现并通过了所有测试。相比单周期版本，CPI 从 55.66 降低到 49.94，提升约 10%。流水线能够正确处理数据冒险（通过转发和 stall）和控制冒险（通过 flush），成功运行 microbench 基准测试套件。
