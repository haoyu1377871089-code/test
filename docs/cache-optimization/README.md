# ICache 优化计划总览

本目录包含 ICache 优化的完整实施计划，按阶段划分为 5 个独立文档。

## 项目背景

根据讲义要求，需要完成以下缓存优化任务：
- 统计 AMAT（Average Memory Access Time）
- 实现 cachesim 用于设计空间探索
- 支持更大的 cache line 和突发传输
- 切换到 AXI 接口 SDRAM
- 实现 AXI4 延迟模块
- 设计空间探索，在面积约束下选择最优方案
- 高级优化（程序内存布局、dcache 分析）

## 面积约束

- **硬性限制**：综合面积 < 25000 μm²
- **推荐限制**：综合面积 < 23000 μm²（为流水线预留）
- **工艺**：nangate45

## 阶段概览

| 阶段 | 文档 | 主要任务 | 预计工作量 |
|------|------|----------|------------|
| 1 | [01-amat-statistics.md](01-amat-statistics.md) | AMAT 统计实现 | 4-6 小时 |
| 2 | [02-cachesim-implementation.md](02-cachesim-implementation.md) | cachesim 实现 | 8-12 小时 |
| 3 | [03-larger-cacheline-burst.md](03-larger-cacheline-burst.md) | 扩展 cache line + 突发传输 | 12-18 小时 |
| 4 | [04-design-space-exploration.md](04-design-space-exploration.md) | 设计空间探索 | 10-15 小时 |
| 5 | [05-advanced-optimization.md](05-advanced-optimization.md) | 高级优化 | 8-12 小时 |

**总预计工作量**：42-63 小时

## 推荐执行顺序

```
阶段 1 (AMAT 统计)
    │
    ▼
阶段 2 (cachesim)
    │
    ├──────────────────┐
    ▼                  ▼
阶段 3 (扩展 cache)   阶段 4.1 (生成 trace)
    │                  │
    │                  ▼
    │              阶段 4.2 (cachesim 评估)
    │                  │
    ▼                  ▼
阶段 3 完成 ◄──────── 阶段 4.3 (确定参数)
    │
    ▼
阶段 4.4 (RTL 实现验证)
    │
    ▼
阶段 5 (高级优化，可选)
```

## 当前项目状态

### ICache
- 容量：4KB
- 组织方式：2-way set-associative
- Cache Line：4 字节
- 替换策略：LRU
- 性能计数器：已有基础实现

### 总线
- 接口：AXI4-Lite
- 突发传输：不支持

### ysyxSoC
- SDRAM 接口：APB（默认）
- AXI4 延迟模块：仅透传

### NEMU
- itrace：已实现
- PC-only 输出：需要添加

## 关键文件索引

### NPC
| 文件 | 说明 |
|------|------|
| `npc/vsrc/core/ICache.v` | ICache 核心实现 |
| `npc/vsrc/core/IFU_AXI.v` | AXI4-Lite Master |
| `npc/vsrc/core/AXI4_Lite_Arbiter.v` | 总线仲裁器 |
| `npc/vsrc/ysyx_00000000.v` | 顶层模块 |

### ysyxSoC
| 文件 | 说明 |
|------|------|
| `ysyxSoC/src/Top.scala` | 配置选项 |
| `ysyxSoC/src/SoC.scala` | SoC 结构 |
| `ysyxSoC/perip/amba/axi4_delayer.v` | AXI4 延迟模块 |

### NEMU
| 文件 | 说明 |
|------|------|
| `nemu/src/cpu/cpu-exec.c` | itrace 实现 |
| `nemu/Kconfig` | 配置选项 |

### 工具（待创建）
| 文件 | 说明 |
|------|------|
| `tools/cachesim/` | cache 模拟器 |
| `scripts/area_estimation.py` | 面积估算 |

## 验收检查清单

### 阶段 1
- [ ] AMAT 统计正确
- [ ] 性能计数器完整
- [ ] 输出格式规范

### 阶段 2
- [ ] cachesim 功能正确
- [ ] 支持多种参数配置
- [ ] 与 RTL 结果一致

### 阶段 3
- [ ] 大 cache line 功能正确
- [ ] 突发传输功能正确
- [ ] AXI SDRAM 工作正常
- [ ] AXI4 延迟模块正确

### 阶段 4
- [ ] 完成设计空间探索
- [ ] 确定最优参数组合
- [ ] 面积满足约束
- [ ] 性能数据有记录

### 阶段 5
- [ ] 评估内存布局优化
- [ ] 完成 dcache 分析
- [ ] 决策有记录

## 性能记录

请在完成各阶段后记录性能数据：

| 配置 | Hit Rate | AMAT | Total Time | 面积 |
|------|----------|------|------------|------|
| 基准（4KB/4B/2-way）| - | - | - | - |
| 配置 1 | - | - | - | - |
| 配置 2 | - | - | - | - |
| 最终配置 | - | - | - | - |

## 参考资料

- 讲义：缓存的优化
- nangate45 工艺库文档
- AXI4 协议规范
- yosys-sta 使用说明
