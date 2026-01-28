# NPC 处理器性能记录

## 测试环境

- **处理器架构**: RISC-V RV32E (单周期/单发射)
- **SoC 环境**: ysyxSoC
- **APB Delayer**: 已启用 (R_TIMES_S=1280, r≈5, s=256)
- **测试程序**: microbench (test 规模, 约550K指令)

## 综合信息 (Yosys 0.9)

|| 项目 | 数值 | 备注 |
||------|------|------|
|| 目标综合频率 | 100 MHz（STA 通过） | OpenSTA 2.0.17：10 ns 周期下 slack 0.06 (MET)；`make sta` 或 `npc/scripts/sta/run_sta.sh`，Liberty 为 yosys_gates.lib 占位延时 |
|| 总单元数 (Cells) | 17,464 | 综合后的逻辑单元 |
|| 触发器 (DFF) | 1,587 | $_DFF_PP0_: 1436, $_DFF_PP1_: 4, $_DFF_P_: 147 |
|| AND 门 | 4,675 | $_AND_ |
|| OR 门 | 4,278 | $_OR_ |
|| MUX 门 | 6,235 | $_MUX_ |
|| XOR 门 | 474 | $_XOR_ |
|| NOT 门 | 215 | $_NOT_ |
|| Wire 数 | 3,762 | 29,714 bits |

## 性能数据记录

### 基线版本 (单周期 NPC + APB Delayer)

|| 测试时间 | Commit | 说明 | 仿真周期数 | 指令数 | IPC | CPI |
||----------|--------|------|------------|--------|-----|-----|
|| 2026-01-25 | fe89758 | 初步: dummy (约23K指令) | 21,314,550 | 23,414 | 0.0011 | 910.33 |
|| 2026-01-25 | fe89758 | microbench (test): 单周期NPC + APB延迟校准 | 522,842,522 | 549,988 | 0.0011 | 950.64 |

### I-Cache 启用版本 (4B Cache Line)

|| 测试时间 | Commit | 说明 | 仿真周期数 | 指令数 | IPC | CPI |
||----------|--------|------|------------|--------|-----|-----|
|| 2026-01-25 | WIP | dummy + ICache | ~4,000,000 | ~23K | ~0.018 | ~55 |
|| 2026-01-25 | WIP | microbench (test) + ICache (98.78% hit rate) | 30,438,401 | 550,084 | 0.018 | 55.33 |

### I-Cache + AXI4 Burst (16B Cache Line)

|| 测试时间 | Commit | 说明 | 仿真周期数 | 指令数 | IPC | CPI |
||----------|--------|------|------------|--------|-----|-----|
|| 2026-01-27 | 5974dd3 | microbench (test) + 16B CacheLine + AXI4 Burst (**99.67% hit**) | 30,786,095 | 550,105 | 0.018 | 55.96 |

### I-Cache + D-Cache (双缓存版本)

|| 测试时间 | Commit | 说明 | 仿真周期数 | 指令数 | IPC | CPI |
||----------|--------|------|------------|--------|-----|-----|
|| 2026-01-28 | WIP | 基线（仅 I-Cache）| 30,593,144 | 549,606 | 0.018 | 55.66 |
|| 2026-01-28 | WIP | I-Cache + D-Cache (**96.65% read hit**) | 24,867,697 | 549,699 | 0.022 | **45.23** |

### 详细性能计数器 (16B Cache Line + AXI4 Burst 版本)

#### EXU 统计
|| 项目 | 数值 | 百分比 |
||------|------|--------|
|| Total Cycles | 30,786,095 | 100% |
|| Retired Instrs | 550,105 | - |
|| IDLE Cycles | 9,164,090 | 29% |
|| EXEC Cycles | 1,650,317 | 5% |
|| WAIT_LSU Cycles | 19,971,688 | 64% |

#### 指令类型分布
|| 指令类型 | 数量 | 百分比 |
||----------|------|--------|
|| ALU R-type | 84,615 | 15% |
|| ALU I-type | 196,534 | 35% |
|| Load | 71,798 | 13% |
|| Store | 56,869 | 10% |
|| Branch | 107,960 (taken: 66,111) | 19% |
|| JAL | 9,987 | 1% |
|| JALR | 12,728 | 2% |
|| LUI | 5,548 | 1% |
|| AUIPC | 4,064 | 0% |
|| CSR | 2 | 0% |

#### I-Cache 统计
|| 项目 | 数值 |
||------|------|
|| Hit Count | 548,320 |
|| Miss Count | 1,786 |
|| Total Accesses | 550,106 |
|| **Hit Rate** | **99.67%** |
|| Total Cycles | 6,413,562 |
|| Refill Cycles | 5,313,350 |
|| Avg Refill Latency | 2,975 cycles |
|| AMAT | 11.65 cycles |

#### IFU/Memory 统计
|| 项目 | 数值 |
||------|------|
|| Mem Fetch Count | 1,786 |
|| Request Cycles | 1,786 |
|| Wait Cycles | 5,307,992 |
|| Arb Stall Cycles | 0 |
|| Avg Mem Latency | 2,972 cycles |

#### LSU 统计
|| 项目 | 数值 |
||------|------|
|| Load Count | 71,798 |
|| Store Count | 56,869 |
|| Load Total Cycles | 13,031,137 |
|| Store Total Cycles | 6,683,217 |
|| Avg Load Latency | 181.49 cycles |
|| Avg Store Latency | 117.51 cycles |

## 优化历史

|| 日期 | Commit | 特性 | 周期数变化 | IPC变化 | 备注 |
||------|--------|------|------------|---------|------|
|| 2026-01-25 | fe89758 | 基线版本 | - | - | 单周期NPC, microbench test CPI≈951 |
|| 2026-01-25 | WIP | I-Cache 修复并启用 | 522M → 30M (**17.18x**) | 0.001 → 0.018 | CPI 从 951 降至 55 |
|| 2026-01-27 | 5974dd3 | 16B CacheLine + AXI4 Burst | 30.4M → 30.8M | - | Hit Rate 98.78% → 99.67%, Miss 6690 → 1786 (**3.74x fewer**) |
|| 2026-01-28 | WIP | D-Cache 启用 | 30.6M → 24.9M (**18.7% 减少**) | 0.018 → 0.022 | CPI 55.66 → 45.23 (**18.7% 改善**) |

## I-Cache 优化效果对比

### 4B vs 16B Cache Line 对比

|| 指标 | 4B Cache Line | 16B Cache Line | 变化 |
||------|---------------|----------------|------|
|| Cache Line 大小 | 4 Bytes | 16 Bytes | 4x |
|| Hit Count | 543,395 | 548,320 | +4,925 |
|| Miss Count | 6,690 | 1,786 | **-73.3%** |
|| Hit Rate | 98.78% | **99.67%** | +0.89% |
|| Avg Refill Latency | 746 cycles | 2,975 cycles | 4x (突发传输) |
|| AMAT | - | 11.65 cycles | - |
|| 总周期数 | 30,438,401 | 30,786,095 | +1.1% |

### 分析

1. **Miss 次数大幅减少**: 从 6,690 降至 1,786 (**73.3% 减少**)，因为更大的 cache line 带来更好的空间局部性
2. **Hit Rate 提升**: 从 98.78% 提升至 99.67%
3. **单次 Refill 延迟增加**: 从 746 cycles 增加到 2,975 cycles (约 4x)，因为需要传输 4 个字而不是 1 个
4. **总周期略有增加**: 从 30.4M 增加到 30.8M (+1.1%)，因为突发传输本身的开销
5. **突发传输收益有限**: 当前 SDRAM 访问延迟较高，突发传输节省的开销比例较小

## I-Cache 设计参数

### 当前配置 (16B Cache Line)

|| 参数 | 数值 | 说明 |
||------|------|------|
|| 总大小 | 4 KB | 中等大小，平衡面积与命中率 |
|| 关联度 | 2-way | 降低冲突 miss |
|| 块大小 | 16 Bytes | 4 words，启用 AXI4 burst |
|| 组数 | 128 sets | 4KB / 2-way / 16B = 128 |
|| 地址划分 | Tag[31:9] Index[8:4] Offset[3:0] | 23-bit tag, 5-bit index, 4-bit offset |
|| 替换策略 | LRU | 2-way 只需 1 bit per set |
|| AXI4 Burst | INCR, len=3 | 4-beat burst (16 bytes) |

### 实现文件
- `npc/vsrc/core/ICache.v` - 参数化 I-Cache 模块
- `npc/vsrc/core/IFU_AXI4.v` - AXI4 Master (支持 burst)
- `npc/vsrc/core/AXI4_Arbiter.v` - AXI4 仲裁器
- `npc/vsrc/core/LSU_AXI4.v` - LSU AXI4 Master
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

## D-Cache 优化效果分析 (2026-01-28)

### 基线 vs D-Cache 启用版本对比

|| 指标 | 仅 I-Cache | I-Cache + D-Cache | 变化 |
||------|------------|-------------------|------|
|| Total Cycles | 30,593,144 | 24,867,697 | **-18.7%** |
|| CPI | 55.66 | **45.23** | **-18.7%** |
|| WAIT_LSU 占比 | 65% | 56% | -9% |
|| Load 延迟 | 185.75 cycles | 170.35 cycles | -8.3% |
|| Store 延迟 | 107.22 cycles | 107.22 cycles | 不变 |

### D-Cache 详细统计

|| 项目 | 数值 |
||------|------|
|| Read Hit Count | 29,471 |
|| Read Miss Count | 1,019 |
|| Write Hit Count | 8,744 |
|| Write Miss Count | 21,014 |
|| Total Accesses | 129,047 |
|| **Read Hit Rate** | **96.65%** |
|| Total Cycles | 14,044,328 |
|| Refill Cycles | 952,765 |
|| Write Cycles | 5,913,378 |
|| Avg Refill Latency | 935 cycles |
|| AMAT | 108.83 cycles |

### 分析

1. **周期数大幅减少**: 从 30.6M 降至 24.9M，减少 **572 万周期 (18.7%)**
2. **CPI 显著改善**: 从 55.66 降至 45.23，改善 **18.7%**
3. **Read Hit Rate 优秀**: 96.65% 的读命中率，减少了大量 PSRAM 访问
4. **Write-through 策略**: 写操作延迟不变，因为所有写都直接写穿到内存
5. **WAIT_LSU 占比下降**: 从 65% 降至 56%，仍是主要瓶颈，但有所改善

### D-Cache 设计参数

|| 参数 | 数值 | 说明 |
||------|------|------|
|| 总大小 | 4 KB | 与 I-Cache 相同 |
|| 关联度 | 2-way | 降低冲突 miss |
|| 块大小 | 16 Bytes | 4 words，启用 AXI4 burst |
|| 写策略 | Write-through | 所有写立即写入内存 |
|| 分配策略 | No-write-allocate | 写 miss 不填充 cache |
|| 可缓存区域 | PSRAM (0x80000000) | I/O 设备自动 bypass |

### 启用方法

在 `npc/Makefile.soc` 中默认启用，可通过 `NO_DCACHE=1` 禁用:
```makefile
# 禁用 D-Cache
make -f Makefile.soc NO_DCACHE=1

# 启用 D-Cache（默认）
make -f Makefile.soc
```

## 注意事项

1. **APB Delayer 参数**: R_TIMES_S=1280 对应 CPU频率≈500MHz, 设备频率≈100MHz
2. **IFU 延迟**: 从 PSRAM 取指延迟约 900 周期（受 APB delayer 影响）
3. **LSU 延迟**: 访问 SRAM 延迟约 4 周期
4. **一致性检查**: 
   - IFU Fetch ~= Retired Instrs (允许差1，因为 ebreak 时有预取) - 已修复为 PASS
   - Sum of Instr Types = Retired (应该 PASS)
5. **D-Cache 启用后**: EXU Load ≠ LSU Load 是正常的，因为 D-Cache hit 不触发 LSU 访存
