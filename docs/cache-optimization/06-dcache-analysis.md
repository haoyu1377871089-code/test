# D-Cache 必要性分析

## 结论摘要

| 问题 | 答案 |
|------|------|
| **是否需要 D-Cache?** | **强烈建议实现** |
| **当前瓶颈** | 64% CPU 时间等待数据访存 |
| **预期 CPI 提升** | 55.96 → ~22-34 (**1.6x - 2.5x**) |
| **推荐方案** | 4KB, 2-way, 16B line, Write-Back |

---

## 当前性能瓶颈分析

基于 microbench (test) 的性能计数器数据 (16B I-Cache Line + AXI4 Burst):

### EXU 状态分布

| 状态 | 周期数 | 百分比 |
|------|--------|--------|
| IDLE (等待取指) | 9,164,090 | 29% |
| EXEC (执行) | 1,650,317 | 5% |
| **WAIT_LSU (等待访存)** | **19,971,688** | **64%** |
| **总计** | **30,786,095** | 100% |

**关键发现：CPU 64% 的时间都在等待 LSU 完成！**

### 数据访存统计

| 指标 | 数值 |
|------|------|
| Load 次数 | 71,798 |
| Store 次数 | 56,869 |
| **总访存次数** | **128,667** |
| Load 总周期 | 13,031,137 |
| Store 总周期 | 6,683,217 |
| Avg Load Latency | 181.49 cycles |
| Avg Store Latency | 117.51 cycles |

### 对比 I-Cache

| 指标 | I-Cache | 数据访存 (无 D-Cache) |
|------|---------|----------------------|
| 访问次数 | 550,106 | 128,667 |
| Hit Rate | 99.67% | 0% (无缓存) |
| Avg Latency | 11.65 cycles (AMAT) | 181.49 cycles (Load) |
| 占 CPU 时间 | 29% (IDLE) | **64% (WAIT_LSU)** |

---

## D-Cache 性能提升预估

### 假设条件

- D-Cache: 4KB, 2-way, 16B line (与 I-Cache 相同配置)
- 假设数据局部性较好，Hit Rate ≈ 90-95%
- Hit Latency: 2 cycles
- Miss Penalty: ~181 cycles (当前 Load 延迟)

### 计算

#### 当前 (无 D-Cache)

```
Load 总周期 = 71,798 × 181.49 = 13,031,137 cycles
Store 总周期 = 56,869 × 117.51 = 6,683,217 cycles
数据访存总周期 = 19,714,354 cycles
```

#### 有 D-Cache (假设 90% Hit Rate)

```
Load Hit 周期 = 71,798 × 90% × 2 = 129,236 cycles
Load Miss 周期 = 71,798 × 10% × 181.49 = 1,303,114 cycles
Load 总周期 = 1,432,350 cycles

Store (Write-Through, No-Allocate):
Store 总周期 ≈ 56,869 × 117.51 = 6,683,217 cycles (无变化)

或 Store (Write-Back):
Store Hit 周期 = 56,869 × 90% × 2 = 102,364 cycles
Store Miss 周期 = 56,869 × 10% × 117.51 = 668,322 cycles
Store 总周期 = 770,686 cycles
```

#### 性能提升预估

| 场景 | Load 周期 | Store 周期 | 总数据访存 | 相比当前 |
|------|-----------|------------|------------|----------|
| 当前 (无 D-Cache) | 13,031,137 | 6,683,217 | 19,714,354 | 1x |
| D-Cache 90% Hit (Write-Through) | 1,432,350 | 6,683,217 | 8,115,567 | **2.43x** |
| D-Cache 90% Hit (Write-Back) | 1,432,350 | 770,686 | 2,203,036 | **8.95x** |
| D-Cache 95% Hit (Write-Back) | 787,757 | 443,507 | 1,231,264 | **16.0x** |

### 总 CPI 预估

| 场景 | 数据访存周期 | IDLE 周期 | EXEC 周期 | 总周期 | CPI |
|------|-------------|-----------|-----------|--------|-----|
| 当前 | 19,971,688 | 9,164,090 | 1,650,317 | 30,786,095 | 55.96 |
| D-Cache 90% (WT) | 8,115,567 | 9,164,090 | 1,650,317 | 18,929,974 | **34.41** |
| D-Cache 90% (WB) | 2,203,036 | 9,164,090 | 1,650,317 | 13,017,443 | **23.66** |
| D-Cache 95% (WB) | 1,231,264 | 9,164,090 | 1,650,317 | 12,045,671 | **21.90** |

---

## 结论与建议

### 是否需要 D-Cache?

**强烈建议实现 D-Cache！**

理由：
1. **当前瓶颈明确**: 64% 的 CPU 时间在等待数据访存
2. **潜在提升巨大**: CPI 可从 55.96 降至 ~22-34 (**1.6x - 2.5x 提升**)
3. **投资回报高**: 相比 I-Cache 的 17x 提升，D-Cache 可再带来 1.6x-2.5x

### 推荐实现方案

#### 方案 A: Write-Through + No-Allocate (简单)

- **优点**: 实现简单，无需处理 dirty bit 和写回
- **缺点**: Store 不加速
- **预计 CPI**: ~34 (1.6x 提升)

```
D-Cache 配置:
- Size: 4KB
- Associativity: 2-way
- Line Size: 16B (4 words)
- Write Policy: Write-Through
- Allocate Policy: No-Write-Allocate
```

#### 方案 B: Write-Back + Write-Allocate (复杂但高效)

- **优点**: Load 和 Store 都加速
- **缺点**: 需要 dirty bit，eviction 时需写回
- **预计 CPI**: ~22-24 (2.3x - 2.5x 提升)

```
D-Cache 配置:
- Size: 4KB
- Associativity: 2-way
- Line Size: 16B (4 words)
- Write Policy: Write-Back
- Allocate Policy: Write-Allocate
- Dirty Bit: 1 bit per line
```

### 建议实现顺序

1. **Phase 1**: 实现 Write-Through D-Cache (验证正确性)
2. **Phase 2**: 升级为 Write-Back (提升性能)
3. **Phase 3**: 考虑非阻塞 Cache (进一步优化)

---

## 附录：访存地址分布分析

要更精确预估 D-Cache Hit Rate，需要分析数据访存的地址分布：

### 需要收集的统计数据

1. **访存地址范围**: 数据访问的地址空间大小
2. **栈访问比例**: 局部变量访问通常有很高的时间局部性
3. **堆访问比例**: 动态分配数据的访问模式
4. **全局变量访问**: 通常分布较分散

### 可添加的性能计数器

```verilog
// 在 LSU_AXI4.v 或 EXU.v 中添加
reg [63:0] perf_lsu_stack_access;    // 栈访问 (sp ± offset)
reg [63:0] perf_lsu_heap_access;     // 堆访问
reg [63:0] perf_lsu_global_access;   // 全局变量访问
reg [31:0] perf_lsu_addr_min;        // 最小访问地址
reg [31:0] perf_lsu_addr_max;        // 最大访问地址
```

---

## D-Cache 实现规划

### Phase 1: Write-Through D-Cache (简单版本)

**目标**: 验证正确性，获得基本性能提升

```verilog
module DCache #(
    parameter CACHE_SIZE = 4096,  // 4KB
    parameter LINE_SIZE  = 16,    // 16B (4 words)
    parameter NUM_WAYS   = 2      // 2-way
) (
    // CPU interface
    input        cpu_req,
    input        cpu_wen,
    input [31:0] cpu_addr,
    input [31:0] cpu_wdata,
    input [3:0]  cpu_wmask,
    output       cpu_rvalid,
    output[31:0] cpu_rdata,
    
    // Memory interface (to LSU_AXI4)
    output       mem_req,
    output       mem_wen,
    output[31:0] mem_addr,
    output[31:0] mem_wdata,
    output[3:0]  mem_wmask,
    output[7:0]  mem_len,      // Burst length for refill
    input        mem_rvalid,
    input [31:0] mem_rdata,
    input        mem_rlast,
    input        mem_bvalid    // Write response
);
```

**预期结果**: CPI ~34 (1.6x 提升)

### Phase 2: Write-Back D-Cache (高效版本)

**目标**: 最大化性能提升

额外需要:
- `dirty` bit 数组
- Eviction 时的写回逻辑
- Write-Allocate 策略

**预期结果**: CPI ~22-24 (2.3x - 2.5x 提升)

---

## 参考：目标系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    ysyx_00000000                        │
│                                                         │
│  ┌─────┐    ┌─────────┐    ┌──────────┐                │
│  │ EXU │◄───│ ICache  │◄───│ IFU_AXI4 │◄──┐            │
│  │     │    │ (4KB)   │    │ (Burst)  │   │            │
│  └──┬──┘    └─────────┘    └──────────┘   │            │
│     │                                      │ AXI4       │
│     │       ┌─────────┐    ┌──────────┐   │ Arbiter    │
│     └──────►│ DCache  │◄───│ LSU_AXI4 │◄──┤            │
│             │ (4KB)   │    │ (Burst)  │   │            │
│             └─────────┘    └──────────┘   │            │
│                                           │            │
└───────────────────────────────────────────┼────────────┘
                                            │
                                            ▼
                                       ysyxSoC
                                    (SDRAM/SRAM)
```

---

## 实现优先级

1. **高优先级**: 实现 Write-Through D-Cache
   - 验证 Cache 一致性
   - 获得 Load 加速

2. **中优先级**: 升级为 Write-Back
   - Store 也能加速
   - CPI 进一步下降

3. **低优先级**: 非阻塞 Cache / MSHR
   - 允许多个 outstanding miss
   - 进一步隐藏延迟
