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

## 注意事项

1. **APB Delayer 参数**: R_TIMES_S=1280 对应 CPU频率≈500MHz, 设备频率≈100MHz
2. **IFU 延迟**: 从 PSRAM 取指延迟约 900 周期（受 APB delayer 影响）
3. **LSU 延迟**: 访问 SRAM 延迟约 4 周期
4. **一致性检查**: 
   - IFU Fetch ~= Retired Instrs (允许差1，因为 ebreak 时有预取) - 已修复为 PASS
   - Sum of Instr Types = Retired (应该 PASS)
