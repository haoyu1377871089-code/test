# 阶段五：高级优化计划

## 任务目标

探索更高级的缓存优化技术，包括程序内存布局优化、dcache 性价比分析等。

---

## Part A：程序内存布局优化

### 背景

程序的内存布局会影响 cache 性能。当热点循环未对齐到 cache line 边界时，可能多占用 cache block。

**示例**：
```
热点循环: [0x1c, 0x34), 16B cache line

未对齐时占用 3 个 cache block:
[0x10-0x1f] [0x20-0x2f] [0x30-0x3f]
       xxxx  xxxxxxxx  xxxx

填充 4B 后占用 2 个 cache block:
[0x20-0x2f] [0x30-0x3f]
 xxxxxxxx   xxxxxx
```

### 步骤 A1：分析热点代码位置

**使用 objdump 分析**：

```bash
# 反汇编并找到热点循环
riscv64-unknown-elf-objdump -d am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.elf | less

# 或使用 nm 查看符号地址
riscv64-unknown-elf-nm am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.elf | grep -E "benchmark|test"
```

**分析脚本**：`scripts/analyze_hotspots.py`

```python
#!/usr/bin/env python3
"""
分析程序热点并检查 cache line 对齐
"""

import subprocess
import re
import sys

def parse_objdump(elf_file):
    """解析 objdump 输出，获取函数地址"""
    result = subprocess.run(
        ['riscv64-unknown-elf-objdump', '-d', elf_file],
        capture_output=True, text=True
    )
    
    functions = {}
    current_func = None
    current_start = None
    
    for line in result.stdout.split('\n'):
        # 函数开始
        match = re.match(r'^([0-9a-f]+)\s+<(\w+)>:', line)
        if match:
            if current_func:
                functions[current_func] = (current_start, current_start)
            current_func = match.group(2)
            current_start = int(match.group(1), 16)
        
        # 指令行
        match = re.match(r'^\s*([0-9a-f]+):', line)
        if match and current_func:
            addr = int(match.group(1), 16)
            functions[current_func] = (current_start, addr + 4)
    
    return functions

def analyze_alignment(functions, line_size=16):
    """分析函数的 cache line 对齐情况"""
    print(f"Cache Line Size: {line_size} bytes\n")
    print(f"{'Function':<30} {'Start':>10} {'End':>10} {'Size':>8} {'Lines':>6} {'Waste':>8}")
    print("-" * 80)
    
    for name, (start, end) in sorted(functions.items(), key=lambda x: x[1][1] - x[1][0], reverse=True)[:20]:
        size = end - start
        
        # 计算占用的 cache line 数
        first_line = start // line_size
        last_line = (end - 1) // line_size
        lines_used = last_line - first_line + 1
        
        # 理想情况下需要的 cache line 数
        ideal_lines = (size + line_size - 1) // line_size
        
        # 浪费的空间
        wasted = lines_used - ideal_lines
        
        print(f"{name:<30} 0x{start:08x} 0x{end:08x} {size:>8} {lines_used:>6} {wasted:>8}")

def suggest_padding(functions, hot_functions, line_size=16):
    """建议填充字节数"""
    print("\n" + "=" * 80)
    print("Alignment Optimization Suggestions")
    print("=" * 80 + "\n")
    
    for name in hot_functions:
        if name not in functions:
            print(f"Warning: Function '{name}' not found")
            continue
        
        start, end = functions[name]
        misalign = start % line_size
        
        if misalign != 0:
            padding = line_size - misalign
            print(f"{name}:")
            print(f"  Current start: 0x{start:08x} (offset {misalign} from line boundary)")
            print(f"  Suggested padding: {padding} bytes before .text section")
            print(f"  New start would be: 0x{start + padding:08x}\n")
        else:
            print(f"{name}: Already aligned to cache line boundary\n")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python analyze_hotspots.py <elf_file> [hot_function1 hot_function2 ...]")
        sys.exit(1)
    
    elf_file = sys.argv[1]
    hot_functions = sys.argv[2:] if len(sys.argv) > 2 else []
    
    functions = parse_objdump(elf_file)
    analyze_alignment(functions)
    
    if hot_functions:
        suggest_padding(functions, hot_functions)
```

### 步骤 A2：修改链接脚本添加填充

**方法 1：修改链接脚本**

编辑 `abstract-machine/scripts/linker.ld`：

```ld
SECTIONS {
    . = 0x30000000;  /* 起始地址 */
    
    .text : {
        /* 添加填充以对齐热点代码 */
        . = ALIGN(16);  /* 对齐到 16 字节（cache line 大小）*/
        /* 或者添加固定填充 */
        /* . = . + 4; */  /* 添加 4 字节填充 */
        
        *(.text)
        *(.text.*)
    }
    
    /* ... 其他段 ... */
}
```

**方法 2：使用编译器属性**

```c
// 对齐特定函数
void __attribute__((aligned(16))) hot_function(void) {
    // ...
}

// 或使用 section 属性将热点代码放在特定位置
void __attribute__((section(".text.hot"))) hot_function(void) {
    // ...
}
```

**方法 3：汇编填充**

在启动代码中添加：

```asm
.section .text
.global _start
_start:
    .balign 16      # 对齐到 16 字节边界
    # 或者
    .space 4        # 添加 4 字节空白
    
    # ... 原有代码 ...
```

### 步骤 A3：评估优化效果

**对比测试脚本**：

```bash
#!/bin/bash

# 1. 基准测试（无填充）
echo "=== Baseline (no padding) ==="
make -C am-kernels/benchmarks/microbench ARCH=riscv32e-ysyxsoc clean all
cp am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin baseline.bin
make -C npc ARCH=riscv32e-ysyxsoc run IMAGE=baseline.bin 2>&1 | tee baseline.log

# 2. 优化测试（添加填充）
echo "=== Optimized (with padding) ==="
# 修改链接脚本或汇编后重新编译
make -C am-kernels/benchmarks/microbench ARCH=riscv32e-ysyxsoc clean all
cp am-kernels/benchmarks/microbench/build/microbench-riscv32e-ysyxsoc.bin optimized.bin
make -C npc ARCH=riscv32e-ysyxsoc run IMAGE=optimized.bin 2>&1 | tee optimized.log

# 3. 对比结果
echo "=== Comparison ==="
grep "Hit Rate\|AMAT\|Total time" baseline.log > baseline_stats.txt
grep "Hit Rate\|AMAT\|Total time" optimized.log > optimized_stats.txt
diff -y baseline_stats.txt optimized_stats.txt
```

---

## Part B：DCache 性价比分析

### 背景

讲义要求评估 dcache 的性价比，考虑：
1. 理想情况下的性能收益
2. dcache 的实现复杂度（需要支持写操作）
3. 面积开销
4. 是否值得用 dcache 的面积扩大 icache

### 步骤 B1：估算 DCache 理想性能收益

**分析当前 LSU 访存模式**：

```bash
# 修改 NEMU 输出数据访问 trace
# 包含：地址、读/写、大小

# 然后用类似 cachesim 的工具分析
```

**数据 trace 格式**：
```
R 0xa0001000 4    # 读 4 字节
W 0xa0001004 4    # 写 4 字节
R 0xa0001008 2    # 读 2 字节
```

**dcache 模拟器扩展**：

```c
typedef enum {
    ACCESS_READ,
    ACCESS_WRITE
} AccessType;

typedef struct {
    // ... 原有字段 ...
    bool dirty;  // 脏位，用于写回策略
} DcacheLine;

bool dcache_access(Cache *cache, uint32_t addr, AccessType type) {
    // ... 类似 icache，但需要处理写操作
    
    if (type == ACCESS_WRITE) {
        // 写命中：更新数据，设置脏位
        // 写缺失：根据策略决定是否分配
    }
}
```

### 步骤 B2：面积估算

**DCache 额外开销**：

| 组件 | ICache | DCache 额外 | 说明 |
|------|--------|-------------|------|
| 数据存储 | 相同 | 0 | - |
| Tag 存储 | 相同 | 0 | - |
| Valid 位 | 相同 | 0 | - |
| Dirty 位 | 0 | num_lines | 写回策略需要 |
| 写缓冲 | 0 | ~200-500 | 可选优化 |
| 控制逻辑 | 基础 | +300-500 | 写状态机 |
| 端口 | 只读 | 读写 | 可能需要双端口 |

**估算公式**：
```
DCache_area ≈ ICache_area + dirty_bits + write_buffer + extra_control
           ≈ ICache_area * 1.15 ~ 1.3
```

### 步骤 B3：性价比计算

**定义**：
```
性价比 = 性能提升 / 面积开销

其中：
- 性能提升 = (原 IPC - 新 IPC) / 原 IPC
- 面积开销 = DCache 面积
```

**分析场景**：

1. **添加 DCache**：
   - 面积开销：约 icache 面积的 1.2 倍
   - 性能提升：取决于数据访问模式

2. **用 DCache 面积扩大 ICache**：
   - 面积开销：相同
   - 性能提升：更高的 icache hit rate

**决策框架**：

```python
def analyze_dcache_tradeoff(icache_area, dcache_overhead_ratio, 
                            icache_hit_improvement, dcache_tmt_reduction):
    """
    分析 dcache vs 扩大 icache 的权衡
    
    参数：
    - icache_area: 当前 icache 面积
    - dcache_overhead_ratio: dcache 相对于同容量 icache 的面积比例
    - icache_hit_improvement: 扩大 icache 后命中率提升
    - dcache_tmt_reduction: 添加 dcache 后数据访问 TMT 减少
    """
    
    # 方案 1：添加 dcache
    dcache_area = icache_area * dcache_overhead_ratio
    total_area_1 = icache_area + dcache_area
    benefit_1 = dcache_tmt_reduction
    
    # 方案 2：扩大 icache（使用 dcache 的面积）
    # 假设面积翻倍，容量翻倍
    total_area_2 = icache_area + dcache_area
    benefit_2 = icache_hit_improvement  # 需要用 cachesim 评估
    
    # 比较
    print(f"方案 1 (添加 dcache):")
    print(f"  面积: {total_area_1:.0f}")
    print(f"  性能收益: {benefit_1:.2f}")
    print(f"  性价比: {benefit_1/total_area_1:.6f}")
    
    print(f"\n方案 2 (扩大 icache):")
    print(f"  面积: {total_area_2:.0f}")
    print(f"  性能收益: {benefit_2:.2f}")
    print(f"  性价比: {benefit_2/total_area_2:.6f}")
```

### 步骤 B4：决策记录

**记录模板**：

```markdown
# DCache 性价比分析报告

## 日期：YYYY-MM-DD

## 当前状态
- ICache 配置：XXX
- ICache 面积：XXX
- 当前 IPC：XXX

## DCache 分析

### 理想性能收益
- 数据访问 miss rate：XX%
- 预计 TMT 减少：XX cycles
- 预计 IPC 提升：XX%

### 面积开销
- 同容量 DCache 面积：XXX
- 额外开销（dirty bits, 控制逻辑）：XXX
- 总面积：XXX

### 实现复杂度
- 需要支持写操作
- 写回/写穿策略选择
- 与 LSU 的接口修改
- 预计开发时间：XX 小时

## 替代方案：扩大 ICache

- 新 ICache 配置：XXX
- 新 ICache 面积：XXX
- 预计命中率提升：XX%
- 预计 TMT 减少：XX cycles

## 结论

[ ] 添加 DCache
[ ] 扩大 ICache
[ ] 维持现状

理由：XXX
```

---

## Part C：面积优化技巧

### 优化方向

1. **逻辑优化**
   - 合并冗余逻辑
   - 简化状态机
   - 复用计算单元

2. **存储优化**
   - 减少冗余存储
   - 使用更紧凑的编码

3. **权衡优化**
   - 时间换空间：重新计算而非存储
   - 注意对关键路径的影响

### 具体技巧

**技巧 1：简化 LRU**

对于 2-way 组相联，LRU 只需 1 bit/set。但对于多路，可以用近似 LRU：

```verilog
// 精确 LRU (4-way 需要 3 bits/set)
// 近似 LRU: 只记录最近访问的 way (2 bits/set)
reg [1:0] recent_way [0:NUM_SETS-1];

// 替换时选择非最近访问的 way
wire [1:0] victim_way = recent_way[index] ^ 2'b11;  // 简化
```

**技巧 2：压缩 Tag 存储**

如果地址空间有限，可以减少 tag 位数：

```verilog
// 原始：21 bits tag
// 如果只访问 0x80000000-0x8FFFFFFF，高 4 位固定
// 可以只存储 17 bits tag
```

**技巧 3：共享比较器**

对于组相联，可以时分复用比较器：

```verilog
// 原始：每路一个比较器
wire hit_way0 = (tag0 == req_tag);
wire hit_way1 = (tag1 == req_tag);

// 优化：复用比较器，分两周期完成
// 代价：增加 1 周期延迟
reg check_way;
wire current_tag = check_way ? tag1 : tag0;
wire tag_match = (current_tag == req_tag);
```

### yosys-sta 使用

```bash
cd yosys-sta

# 综合
make synth TOP=ysyx_00000000

# 查看面积报告
cat reports/area.rpt

# 查看时序报告
cat reports/timing.rpt
```

---

## 验收标准

### Part A：内存布局优化
- [ ] 完成热点代码分析
- [ ] 实现填充机制
- [ ] 对比测试结果有记录
- [ ] 评估优化效果

### Part B：DCache 性价比分析
- [ ] 估算 DCache 理想性能收益
- [ ] 估算 DCache 面积开销
- [ ] 完成与扩大 ICache 的对比
- [ ] 决策有记录和理由

### Part C：面积优化
- [ ] 应用至少一种优化技巧
- [ ] yosys-sta 验证面积
- [ ] 最终面积 < 25000 μm²

## 相关文件

| 文件 | 说明 |
|------|------|
| `scripts/analyze_hotspots.py` | 热点分析脚本 |
| `abstract-machine/scripts/linker.ld` | 链接脚本 |
| `docs/cache-optimization/dcache_analysis.md` | DCache 分析报告 |

## 预计工作量

- Part A（内存布局优化）：3-4 小时
- Part B（DCache 分析）：4-6 小时
- Part C（面积优化）：2-4 小时
