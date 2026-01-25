# NPC 处理器性能记录

## 测试环境

- **处理器架构**: RISC-V RV32E (单周期/单发射)
- **SoC 环境**: ysyxSoC
- **APB Delayer**: 已启用 (R_TIMES_S=1280, r≈5, s=256)
- **测试程序**: microbench (test 规模, 约550K指令)

## 综合信息 (Yosys 0.9)

| 项目 | 数值 | 备注 |
|------|------|------|
| 目标综合频率 | 100 MHz（STA 通过） | OpenSTA 2.0.17：10 ns 周期下 slack 0.06 (MET)；`make sta` 或 `npc/scripts/sta/run_sta.sh`，Liberty 为 yosys_gates.lib 占位延时 |
| 总单元数 (Cells) | 17,464 | 综合后的逻辑单元 |
| 触发器 (DFF) | 1,587 | $_DFF_PP0_: 1436, $_DFF_PP1_: 4, $_DFF_P_: 147 |
| AND 门 | 4,675 | $_AND_ |
| OR 门 | 4,278 | $_OR_ |
| MUX 门 | 6,235 | $_MUX_ |
| XOR 门 | 474 | $_XOR_ |
| NOT 门 | 215 | $_NOT_ |
| Wire 数 | 3,762 | 29,714 bits |

## 性能数据记录

### 基线版本 (单周期 NPC + APB Delayer)

| 测试时间 | Commit | 说明 | 仿真周期数 | 指令数 | IPC | CPI |
|----------|--------|------|------------|--------|-----|-----|
| 2026-01-25 | fe89758 | 初步: dummy (约23K指令) | 21,314,550 | 23,414 | 0.0011 | 910.33 |
| 2026-01-25 | fe89758 | microbench (test): 单周期NPC + APB延迟校准 | 522,842,522 | 549,988 | 0.0011 | 950.64 |

### I-Cache 启用版本

| 测试时间 | Commit | 说明 | 仿真周期数 | 指令数 | IPC | CPI |
|----------|--------|------|------------|--------|-----|-----|
| 2026-01-25 | WIP | dummy + ICache | ~4,000,000 | ~23K | ~0.018 | ~55 |
| 2026-01-25 | WIP | microbench (test) + ICache (98.78% hit rate) | 30,438,401 | 550,084 | 0.018 | 55.33 |

### 详细性能计数器 (microbench test 规模)

#### EXU 统计
| 项目 | 数值 | 百分比 |
|------|------|--------|
| Total Cycles | 522,842,522 | 100% |
| Retired Instrs | 549,988 | - |
| IDLE Cycles | 505,193,532 | 96% |
| EXEC Cycles | 1,649,966 | 0.3% |
| WAIT_LSU Cycles | 15,999,024 | 3% |

#### 指令类型分布
| 指令类型 | 数量 | 百分比 |
|----------|------|--------|
| ALU R-type | 84,615 | 15% |
| ALU I-type | 196,495 | 35% |
| Load | 71,759 | 13% |
| Store | 56,869 | 10% |
| Branch | 107,921 (taken: 66,072) | 19% |
| JAL | 9,987 | 1% |
| JALR | 12,728 | 2% |
| LUI | 5,548 | 1% |
| AUIPC | 4,064 | 0% |
| CSR | 2 | 0% |

#### IFU 统计
| 项目 | 数值 |
|------|------|
| Fetch Count | 549,989 |
| Request Cycles | 549,989 |
| Wait Cycles | 501,893,600 |
| Arb Stall Cycles | 8,003,478 |
| Avg Fetch Latency | 912.55 cycles |

#### LSU 统计
| 项目 | 数值 |
|------|------|
| Load Count | 71,759 |
| Store Count | 56,869 |
| Load Total Cycles | 15,855,506 |
| Store Total Cycles | 8,181,346 |
| Avg Load Latency | 220.95 cycles |
| Avg Store Latency | 143.86 cycles |

## 优化历史

| 日期 | Commit | 特性 | 周期数变化 | IPC变化 | 备注 |
|------|--------|------|------------|---------|------|
| 2026-01-25 | fe89758 | 基线版本 | - | - | 单周期NPC, microbench test CPI≈951 |
| 2026-01-25 | WIP | I-Cache 修复并启用 | 522M → 30M (**17.18x**) | 0.001 → 0.018 | CPI 从 951 降至 55 |

## I-Cache 优化效果 (2026-01-25 已修复)

### 性能对比
| 指标 | 基线（无 ICache） | 启用 ICache | 提升倍数 |
|------|-------------------|-------------|----------|
| 总周期数 | 522,842,522 | 30,438,401 | **17.18x** |
| CPI | 950.64 | 55.33 | **17.18x** |
| IPC | 0.0011 | 0.018 | **17.18x** |

### I-Cache 统计 (microbench test)
| 项目 | 数值 |
|------|------|
| Hit Count | 543,395 |
| Miss Count | 6,690 |
| **Hit Rate** | **98.78%** |
| Refill Cycles | 4,990,740 |
| Avg Refill Latency | 746 cycles |

### EXU 状态分布变化
| 状态 | 基线 | 启用 ICache | 说明 |
|------|------|-------------|------|
| IDLE | 96% (505M) | 29% (8.8M) | 大幅减少等待取指时间 |
| EXEC | 0.3% (1.6M) | 5% (1.6M) | 执行周期相同 |
| WAIT_LSU | 3% (16M) | 65% (20M) | 占比提高（因总周期减少） |

### 详细性能计数器 (ICache 启用后)

#### EXU 统计
| 项目 | 数值 | 百分比 |
|------|------|--------|
| Total Cycles | 30,438,401 | 100% |
| Retired Instrs | 550,084 | - |
| IDLE Cycles | 8,841,333 | 29% |
| EXEC Cycles | 1,650,254 | 5% |
| WAIT_LSU Cycles | 19,946,814 | 65% |

#### IFU/Memory 统计
| 项目 | 数值 |
|------|------|
| Mem Fetch Count | 6,690 |
| Request Cycles | 6,690 |
| Wait Cycles | 4,970,670 |
| Arb Stall Cycles | 0 |
| Avg Mem Latency | 743 cycles |

#### LSU 统计
| 项目 | 数值 |
|------|------|
| Load Count | 71,791 |
| Store Count | 56,869 |
| Load Total Cycles | 13,031,081 |
| Store Total Cycles | 6,658,413 |
| Avg Load Latency | 181.51 cycles |
| Avg Store Latency | 117.08 cycles |

## I-Cache 设计参数

| 参数 | 数值 | 说明 |
|------|------|------|
| 总大小 | 4 KB | 中等大小，平衡面积与命中率 |
| 关联度 | 2-way | 降低冲突 miss |
| 块大小 | 4 Bytes | 1 word，简化 refill 逻辑 |
| 组数 | 512 sets | 4KB / 2-way / 4B = 512 |
| 地址划分 | Tag[31:11] Index[10:2] | 21-bit tag, 9-bit index |
| 替换策略 | LRU | 2-way 只需 1 bit per set |

### 实现文件
- `npc/vsrc/core/ICache.v` - I-Cache 模块
- `npc/vsrc/ysyx_00000000.v` - 使用 `ifdef ENABLE_ICACHE` 控制启用

### 启用方法
在 `npc/Makefile.soc` 中添加 `+define+ENABLE_ICACHE`:
```makefile
VERILATOR_CFLAGS += ... +define+SIMULATION +define+ENABLE_ICACHE
```

## 已修复的 Bug (2026-01-25)

### 1. IFU_AXI 并发赋值冲突
- **文件**: `npc/vsrc/core/IFU_AXI.v`
- **问题**: 多个 if 块并发赋值 `rvalid_out` 和 `rready`
- **修复**: 重构为显式状态机 (IFU_IDLE → IFU_WAIT_AR → IFU_WAIT_R)

### 2. AXI 仲裁器事务完成检测过早
- **文件**: `npc/vsrc/core/AXI4_Lite_Arbiter.v`
- **问题**: 地址握手完成后就释放总线，应等待数据/响应完成
- **修复**: 事务完成条件改为 `(rvalid && rready)` 或 `(bvalid && bready)`

### 3. EXU store 指令不等待 LSU 完成
- **文件**: `npc/vsrc/core/EXU.v`
- **问题**: store 指令直接跳到 WRITEBACK，与后续 load 指令冲突
- **修复**: store 也进入 WAIT_LSU 状态等待完成

### 4. LSU_AXI 并发赋值冲突（关键 bug）
- **文件**: `npc/vsrc/core/LSU_AXI.v`
- **问题**: 写操作完成时设置的 `rvalid_out=1` 被 else 分支的 `rvalid_out=0` 覆盖
- **修复**: 移除冲突的 else 分支

## 注意事项

1. **APB Delayer 参数**: R_TIMES_S=1280 对应 CPU频率≈500MHz, 设备频率≈100MHz
2. **IFU 延迟**: 从 PSRAM 取指延迟约 900 周期（受 APB delayer 影响）
3. **LSU 延迟**: 访问 SRAM 延迟约 4 周期
4. **一致性检查**: 
   - IFU Fetch ~= Retired Instrs (允许差1，因为 ebreak 时有预取) - 已修复为 PASS
   - Sum of Instr Types = Retired (应该 PASS)
