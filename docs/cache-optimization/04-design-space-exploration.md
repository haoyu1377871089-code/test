# 阶段四：设计空间探索计划

## 任务目标

利用 cachesim 和 ysyxSoC 评估不同 cache 参数组合，在面积约束下选择最优设计方案。

## 面积约束

- **综合面积限制**：< 25000 μm²（B 阶段流片要求）
- **推荐面积**：< 23000 μm²（为流水线预留空间）
- **工艺**：nangate45

## 探索参数空间

### Cache 参数

| 参数 | 探索范围 | 备注 |
|------|----------|------|
| 总容量 | 1KB, 2KB, 4KB, 8KB | 影响 capacity miss |
| Cache Line | 4B, 8B, 16B, 32B | 影响空间局部性 |
| 组相联路数 | 1, 2, 4, 8 | 影响 conflict miss |
| 替换策略 | LRU, FIFO, Random | LRU 通常最优 |

### 传输方式

| 方式 | 缺失代价（估算）| 说明 |
|------|-----------------|------|
| 独立传输 | n × (a+b+c+d) | n = line_size / 4 |
| 突发传输 | a + b + n×c + d | 节省 (n-1)×(a+b+d) |

## 评估流程

```
┌──────────────────────────────────────────────────────────────────┐
│                      设计空间探索流程                              │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. 生成 Trace                                                   │
│     ┌────────┐    ┌────────────┐                                │
│     │  NEMU  │───>│ PC Trace   │                                │
│     └────────┘    └────────────┘                                │
│                          │                                       │
│  2. 快速评估缺失次数      ▼                                       │
│     ┌────────────────────────────────┐                          │
│     │         cachesim               │                          │
│     │  ┌─────┐ ┌─────┐ ┌─────┐      │                          │
│     │  │参数1│ │参数2│ │参数N│ ...  │  并行执行                  │
│     │  └──┬──┘ └──┬──┘ └──┬──┘      │                          │
│     │     │       │       │          │                          │
│     │     ▼       ▼       ▼          │                          │
│     │  miss_cnt miss_cnt miss_cnt    │                          │
│     └────────────────────────────────┘                          │
│                          │                                       │
│  3. 计算 TMT              ▼                                       │
│     TMT = miss_cnt × miss_penalty                                │
│     (miss_penalty 从 ysyxSoC 预先测得)                           │
│                          │                                       │
│  4. 评估面积              ▼                                       │
│     ┌────────────┐                                              │
│     │ yosys-sta  │ → 面积估算                                    │
│     └────────────┘                                              │
│                          │                                       │
│  5. 筛选最优方案          ▼                                       │
│     满足面积约束 且 TMT 最小                                      │
│                          │                                       │
│  6. RTL 实现与验证        ▼                                       │
│     ┌─────────┐    ┌──────────┐    ┌───────────┐               │
│     │ 实现RTL │───>│ysyxSoC仿真│───>│ 性能验证   │               │
│     └─────────┘    └──────────┘    └───────────┘               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## 实现规范

### 步骤 1：生成 Benchmark Trace

**程序选择**：
- microbench train 规模（代表性最好）
- coremark（CPU 密集型）
- dhrystone（综合测试）

**生成方法**：

```bash
# 配置 NEMU 输出 PC-only trace
cd nemu
make menuconfig
# 启用 CONFIG_ITRACE_PC_ONLY

# 运行并生成 trace
make ARCH=riscv32e-nemu run ARGS="-b -l trace_microbench.txt" < /dev/null
```

**trace 压缩**（可选）：

```bash
# 压缩 trace 文件
bzip2 trace_microbench.txt
# 生成 trace_microbench.txt.bz2
```

### 步骤 2：测量缺失代价

在 ysyxSoC 中测量不同配置的平均缺失代价。

**测量脚本**：`tools/cachesim/scripts/measure_penalty.sh`

```bash
#!/bin/bash

# 测量不同 cache line 大小的缺失代价
# 需要在 NPC 中临时实现对应的 cache line 大小

LINE_SIZES="4 8 16 32"
RESULTS="miss_penalty.csv"

echo "line_size,avg_penalty" > $RESULTS

for line_size in $LINE_SIZES; do
    echo "Measuring penalty for line_size=$line_size..."
    
    # 修改 ICache 参数并重新编译
    # 这里需要手动或通过脚本修改 ICache.v 中的 LINE_SIZE 参数
    
    # 运行测试程序（使用 test 规模加速）
    cd /home/hy258/ysyx-workbench/npc
    make ARCH=riscv32e-ysyxsoc run 2>&1 | tee run.log
    
    # 解析 refill cycles 和 miss count
    # 假设性能计数器输出格式为：
    # Avg Miss Penalty:   XX.XX cycles
    penalty=$(grep "Avg Miss Penalty" run.log | awk '{print $4}')
    
    echo "$line_size,$penalty" >> $RESULTS
done

echo "Results saved to $RESULTS"
cat $RESULTS
```

**典型缺失代价参考**：

| Cache Line | 独立传输 | 突发传输 |
|------------|----------|----------|
| 4B | ~70 cycles | ~70 cycles |
| 8B | ~140 cycles | ~85 cycles |
| 16B | ~280 cycles | ~115 cycles |
| 32B | ~560 cycles | ~175 cycles |

*注：实际数值取决于 SDRAM 时序和频率比 r*

### 步骤 3：批量评估 cachesim

**主评估脚本**：`tools/cachesim/scripts/full_dse.sh`

```bash
#!/bin/bash

CACHESIM=/home/hy258/ysyx-workbench/tools/cachesim/cachesim
TRACE=$1
PENALTY_FILE=$2
OUTPUT_DIR=dse_results_$(date +%Y%m%d_%H%M%S)

if [ -z "$TRACE" ] || [ -z "$PENALTY_FILE" ]; then
    echo "Usage: $0 <trace_file> <penalty_file>"
    echo "  penalty_file format: line_size,avg_penalty"
    exit 1
fi

mkdir -p $OUTPUT_DIR

# 读取缺失代价
declare -A PENALTIES
while IFS=',' read -r line_size penalty; do
    if [ "$line_size" != "line_size" ]; then
        PENALTIES[$line_size]=$penalty
    fi
done < $PENALTY_FILE

# 参数空间
SIZES="1024 2048 4096 8192"
LINES="4 8 16 32"
WAYS="1 2 4 8"
POLICIES="L"  # LRU 通常最优，可扩展

# 结果文件
RESULTS=$OUTPUT_DIR/dse_results.csv
echo "size,line,ways,policy,miss_penalty,accesses,hits,misses,hit_rate,tmt" > $RESULTS

total_configs=0
for size in $SIZES; do
    for line in $LINES; do
        for way in $WAYS; do
            # 验证参数有效性
            num_sets=$((size / line / way))
            if [ $num_sets -lt 1 ]; then
                continue
            fi
            total_configs=$((total_configs + 1))
        done
    done
done

echo "Total configurations to evaluate: $total_configs"

current=0
for size in $SIZES; do
    for line in $LINES; do
        for way in $WAYS; do
            for policy in $POLICIES; do
                num_sets=$((size / line / way))
                if [ $num_sets -lt 1 ]; then
                    continue
                fi
                
                current=$((current + 1))
                penalty=${PENALTIES[$line]:-70}
                
                echo -ne "\rEvaluating [$current/$total_configs]: size=$size line=$line ways=$way policy=$policy"
                
                result=$($CACHESIM -s $size -l $line -w $way -r $policy -p $penalty -q "$TRACE")
                echo "$result" >> $RESULTS
            done
        done
    done
done

echo -e "\n\nEvaluation complete!"
echo "Results saved to $RESULTS"

# 生成排序后的报告
echo -e "\n========== Top 20 Configurations by TMT =========="
echo "size,line,ways,policy,miss_penalty,accesses,hits,misses,hit_rate,tmt"
sort -t',' -k10 -n $RESULTS | head -21 | tail -20

# 保存排序结果
sort -t',' -k10 -n $RESULTS > $OUTPUT_DIR/dse_results_sorted_by_tmt.csv
sort -t',' -k9 -rn $RESULTS > $OUTPUT_DIR/dse_results_sorted_by_hitrate.csv
```

### 步骤 4：面积评估

使用 yosys-sta 评估不同配置的面积。

**面积评估脚本**：`scripts/area_estimation.py`

```python
#!/usr/bin/env python3
"""
ICache 面积估算脚本
基于 nangate45 工艺的经验公式
"""

import sys
import math

def estimate_icache_area(total_size, line_size, num_ways):
    """
    估算 ICache 面积
    
    组成部分：
    1. 数据存储阵列
    2. Tag 存储阵列
    3. Valid 位
    4. LRU 位
    5. 比较器
    6. 控制逻辑
    """
    
    num_sets = total_size // line_size // num_ways
    words_per_line = line_size // 4
    
    # 地址分解
    offset_bits = int(math.log2(line_size))
    index_bits = int(math.log2(num_sets))
    tag_bits = 32 - offset_bits - index_bits
    
    # 1. 数据存储（最主要的面积）
    # 每个 SRAM bit 约 0.5-1 um^2 (nangate45)
    data_bits = total_size * 8
    data_area = data_bits * 0.7  # um^2
    
    # 2. Tag 存储
    tag_bits_total = tag_bits * num_sets * num_ways
    tag_area = tag_bits_total * 0.7
    
    # 3. Valid 位
    valid_bits = num_sets * num_ways
    valid_area = valid_bits * 0.5
    
    # 4. LRU 位（简化：每 set 1 bit）
    lru_bits = num_sets
    lru_area = lru_bits * 0.5
    
    # 5. 比较器（每路一个 tag 比较器）
    comparator_area = num_ways * tag_bits * 2  # um^2
    
    # 6. 控制逻辑和 MUX
    control_area = 500 + num_ways * 100 + words_per_line * 50
    
    total_area = data_area + tag_area + valid_area + lru_area + comparator_area + control_area
    
    return {
        'total_size': total_size,
        'line_size': line_size,
        'num_ways': num_ways,
        'num_sets': num_sets,
        'tag_bits': tag_bits,
        'data_area': data_area,
        'tag_area': tag_area,
        'valid_area': valid_area,
        'lru_area': lru_area,
        'comparator_area': comparator_area,
        'control_area': control_area,
        'total_area': total_area
    }

def main():
    print("ICache Area Estimation (nangate45)")
    print("=" * 70)
    print(f"{'Size':>6} {'Line':>6} {'Ways':>6} {'Sets':>6} {'Tag':>4} {'Data':>10} {'Total':>10} {'Status':>10}")
    print("-" * 70)
    
    AREA_LIMIT = 25000
    AREA_RECOMMEND = 23000
    
    configs = []
    
    for size in [1024, 2048, 4096, 8192]:
        for line in [4, 8, 16, 32]:
            for ways in [1, 2, 4, 8]:
                num_sets = size // line // ways
                if num_sets < 1:
                    continue
                    
                result = estimate_icache_area(size, line, ways)
                
                if result['total_area'] < AREA_LIMIT:
                    if result['total_area'] < AREA_RECOMMEND:
                        status = "OK"
                    else:
                        status = "MARGINAL"
                else:
                    status = "EXCEED"
                
                print(f"{size:>6} {line:>6} {ways:>6} {result['num_sets']:>6} "
                      f"{result['tag_bits']:>4} {result['data_area']:>10.0f} "
                      f"{result['total_area']:>10.0f} {status:>10}")
                
                configs.append((result, status))
    
    print("-" * 70)
    print(f"Area limit: {AREA_LIMIT} um^2, Recommended: {AREA_RECOMMEND} um^2")
    print("\nConfigurations meeting recommended limit:")
    for result, status in configs:
        if status == "OK":
            print(f"  {result['total_size']}B, {result['line_size']}B line, "
                  f"{result['num_ways']}-way: {result['total_area']:.0f} um^2")

if __name__ == "__main__":
    main()
```

### 步骤 5：综合分析

**分析脚本**：`tools/cachesim/scripts/analyze_dse.py`

```python
#!/usr/bin/env python3
"""
设计空间探索分析脚本
综合 TMT 和面积数据，选择最优配置
"""

import csv
import sys
from collections import defaultdict

def load_dse_results(filename):
    results = []
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            results.append({
                'size': int(row['size']),
                'line': int(row['line']),
                'ways': int(row['ways']),
                'policy': row['policy'],
                'hit_rate': float(row['hit_rate']),
                'miss_count': int(row['misses']),
                'tmt': int(row['tmt'])
            })
    return results

def estimate_area(size, line, ways):
    """简化的面积估算"""
    num_sets = size // line // ways
    offset_bits = len(bin(line)) - 3  # log2
    index_bits = len(bin(num_sets)) - 3
    tag_bits = 32 - offset_bits - index_bits
    
    data_area = size * 8 * 0.7
    tag_area = tag_bits * num_sets * ways * 0.7
    other_area = 500 + ways * (100 + tag_bits * 2) + (line // 4) * 50
    
    return data_area + tag_area + other_area

def analyze(results, area_limit=25000, area_recommend=23000):
    # 过滤面积超限的配置
    valid_results = []
    for r in results:
        area = estimate_area(r['size'], r['line'], r['ways'])
        r['area'] = area
        if area <= area_limit:
            r['area_status'] = 'OK' if area <= area_recommend else 'MARGINAL'
            valid_results.append(r)
        else:
            r['area_status'] = 'EXCEED'
    
    # 按 TMT 排序
    valid_results.sort(key=lambda x: x['tmt'])
    
    print("=" * 80)
    print("Design Space Exploration Analysis Report")
    print("=" * 80)
    
    print(f"\nTotal configurations evaluated: {len(results)}")
    print(f"Configurations within area limit: {len(valid_results)}")
    print(f"Area limit: {area_limit} um^2, Recommended: {area_recommend} um^2")
    
    print("\n" + "=" * 80)
    print("Top 10 Configurations (by TMT, within area limit)")
    print("=" * 80)
    print(f"{'Rank':>4} {'Size':>6} {'Line':>6} {'Ways':>5} {'Hit%':>8} "
          f"{'TMT':>12} {'Area':>10} {'Status':>10}")
    print("-" * 80)
    
    for i, r in enumerate(valid_results[:10], 1):
        print(f"{i:>4} {r['size']:>6} {r['line']:>6} {r['ways']:>5} "
              f"{r['hit_rate']*100:>7.2f}% {r['tmt']:>12} "
              f"{r['area']:>10.0f} {r['area_status']:>10}")
    
    # 不同维度的分析
    print("\n" + "=" * 80)
    print("Analysis by Cache Size (best TMT for each size)")
    print("=" * 80)
    
    by_size = defaultdict(list)
    for r in valid_results:
        by_size[r['size']].append(r)
    
    for size in sorted(by_size.keys()):
        best = min(by_size[size], key=lambda x: x['tmt'])
        print(f"  {size}B: line={best['line']}B, ways={best['ways']}, "
              f"hit={best['hit_rate']*100:.2f}%, TMT={best['tmt']}, "
              f"area={best['area']:.0f}")
    
    print("\n" + "=" * 80)
    print("Recommendation")
    print("=" * 80)
    
    # 推荐配置
    recommended = [r for r in valid_results if r['area_status'] == 'OK']
    if recommended:
        best = recommended[0]
        print(f"\nBest configuration within recommended area:")
        print(f"  Size: {best['size']} bytes")
        print(f"  Line Size: {best['line']} bytes")
        print(f"  Associativity: {best['ways']}-way")
        print(f"  Hit Rate: {best['hit_rate']*100:.2f}%")
        print(f"  TMT: {best['tmt']} cycles")
        print(f"  Estimated Area: {best['area']:.0f} um^2")
    
    return valid_results

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python analyze_dse.py <dse_results.csv>")
        sys.exit(1)
    
    results = load_dse_results(sys.argv[1])
    analyze(results)
```

### 步骤 6：RTL 实现与最终验证

**验证流程**：

```bash
# 1. 根据 DSE 结果选择最优配置
# 假设选择：4KB, 16B line, 2-way

# 2. 修改 ICache 参数
# 编辑 npc/vsrc/core/ICache.v

# 3. 编译并运行
cd npc
make ARCH=riscv32e-ysyxsoc run

# 4. 验证性能计数器结果与 cachesim 一致

# 5. 运行 microbench train 规模
# 记录最终性能数据

# 6. 运行 yosys-sta 验证面积
cd yosys-sta
make synth
# 确认面积 < 25000 um^2
```

## 决策矩阵

**评估标准权重**：

| 指标 | 权重 | 说明 |
|------|------|------|
| TMT | 40% | 性能最重要 |
| 面积 | 30% | 必须满足约束 |
| 实现复杂度 | 15% | 影响开发时间 |
| 主频影响 | 15% | 更大的 cache 可能增加关键路径 |

**决策公式**：

```
Score = 0.4 * (1 - TMT/TMT_max) + 
        0.3 * (1 - Area/Area_limit) + 
        0.15 * Complexity_score +
        0.15 * Frequency_score
```

## 记录模板

**设计选择记录**：`docs/cache-optimization/design_decision.md`

```markdown
# ICache 设计决策记录

## 日期：YYYY-MM-DD

## 评估环境
- NEMU 版本：xxx
- NPC 版本：xxx
- 测试程序：microbench train

## 评估结果摘要

### 候选配置

| 配置 | TMT | 面积 | 主频 | 得分 |
|------|-----|------|------|------|
| 4KB/4B/2-way | xxx | xxx | xxx | xxx |
| 4KB/16B/2-way | xxx | xxx | xxx | xxx |
| ... | ... | ... | ... | ... |

### 最终选择

- **配置**：XXX
- **理由**：XXX
- **预期性能提升**：XXX
- **面积开销**：XXX

## 实现计划

1. 修改 ICache 参数
2. 实现突发传输
3. 验证功能正确性
4. 性能测试
```

## 验收标准

1. [ ] 生成 benchmark trace 文件
2. [ ] 测量并记录各种 cache line 的缺失代价
3. [ ] cachesim 批量评估完成
4. [ ] 面积评估完成
5. [ ] 生成 DSE 分析报告
6. [ ] 确定最优配置并记录决策理由
7. [ ] RTL 实现并验证性能
8. [ ] 最终面积 < 25000 μm²
9. [ ] 性能数据记录

## 相关文件

| 文件 | 说明 |
|------|------|
| `tools/cachesim/scripts/full_dse.sh` | 批量评估脚本 |
| `tools/cachesim/scripts/analyze_dse.py` | 分析脚本 |
| `scripts/area_estimation.py` | 面积估算脚本 |
| `docs/cache-optimization/design_decision.md` | 决策记录 |

## 预计工作量

- Trace 生成：1-2 小时
- 缺失代价测量：2-3 小时（每种配置需要修改并运行）
- cachesim 批量评估：1-2 小时（自动化）
- 面积评估：1-2 小时
- 分析与决策：2-3 小时
- RTL 实现与验证：4-6 小时
