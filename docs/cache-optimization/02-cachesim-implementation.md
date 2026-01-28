# 阶段二：CacheSim 实现计划

## 任务目标

实现一个简单的 Cache 功能模拟器（cachesim），用于快速评估不同 cache 参数组合的性能表现，支持设计空间探索。

## 设计原理

### 为什么需要 cachesim

1. **效率问题**：在 ysyxSoC 中运行完整程序需要小时级时间，无法高效探索设计空间
2. **关键观察**：
   - cache 缺失次数只与元数据相关，与实际数据无关
   - 给定 PC 序列，cache 行为是确定的
   - 不需要仿真整个 NPC，只需模拟 cache 元数据

### 工作流程

```
NEMU 执行程序 → 生成 itrace（PC 序列）→ cachesim 模拟 → 输出缺失统计
                                              ↓
                                      × 缺失代价（从 ysyxSoC 测得）
                                              ↓
                                      估算 TMT（Total Miss Time）
```

## 实现规范

### 目录结构

```
tools/
└── cachesim/
    ├── Makefile
    ├── README.md
    ├── src/
    │   ├── main.c           # 主程序
    │   ├── cache.c          # cache 模拟核心
    │   ├── cache.h          # cache 数据结构
    │   ├── trace.c          # trace 文件解析
    │   ├── trace.h
    │   ├── stats.c          # 统计输出
    │   └── stats.h
    └── test/
        ├── test_direct.txt  # 测试用 trace
        └── run_tests.sh
```

### 步骤 1：定义数据结构

**文件**：`tools/cachesim/src/cache.h`

```c
#ifndef CACHE_H
#define CACHE_H

#include <stdint.h>
#include <stdbool.h>

// Cache 配置参数
typedef struct {
    uint32_t total_size;      // 总容量（字节）
    uint32_t line_size;       // cache line 大小（字节）
    uint32_t num_ways;        // 组相联路数（1=直接映射）
    char     replace_policy;  // 替换策略：'L'=LRU, 'F'=FIFO, 'R'=Random
} CacheConfig;

// Cache Line 元数据
typedef struct {
    bool     valid;
    uint32_t tag;
    uint32_t lru_counter;     // LRU 计数器
    uint32_t fifo_order;      // FIFO 顺序
} CacheLine;

// Cache Set
typedef struct {
    CacheLine *lines;         // 指向该 set 的所有 way
    uint32_t   fifo_next;     // FIFO 下一个替换位置
} CacheSet;

// Cache 实例
typedef struct {
    CacheConfig config;
    CacheSet   *sets;
    uint32_t    num_sets;
    
    // 地址分解参数
    uint32_t offset_bits;
    uint32_t index_bits;
    uint32_t tag_bits;
    uint32_t offset_mask;
    uint32_t index_mask;
    
    // 统计数据
    uint64_t access_count;
    uint64_t hit_count;
    uint64_t miss_count;
    uint64_t compulsory_miss;  // 冷启动缺失
    uint64_t capacity_miss;    // 容量缺失（需要无限容量 cache 辅助判断）
    uint64_t conflict_miss;    // 冲突缺失
} Cache;

// API
Cache* cache_create(CacheConfig *config);
void   cache_destroy(Cache *cache);
void   cache_reset(Cache *cache);
bool   cache_access(Cache *cache, uint32_t addr);  // 返回是否命中
void   cache_print_stats(Cache *cache);
void   cache_export_csv(Cache *cache, const char *filename);

#endif
```

### 步骤 2：实现 Cache 核心逻辑

**文件**：`tools/cachesim/src/cache.c`

```c
#include "cache.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

// 辅助函数：计算 log2
static uint32_t log2_uint(uint32_t n) {
    uint32_t r = 0;
    while (n >>= 1) r++;
    return r;
}

Cache* cache_create(CacheConfig *config) {
    Cache *cache = (Cache*)malloc(sizeof(Cache));
    if (!cache) return NULL;
    
    memcpy(&cache->config, config, sizeof(CacheConfig));
    
    // 计算参数
    cache->num_sets = config->total_size / config->line_size / config->num_ways;
    cache->offset_bits = log2_uint(config->line_size);
    cache->index_bits = log2_uint(cache->num_sets);
    cache->tag_bits = 32 - cache->offset_bits - cache->index_bits;
    
    cache->offset_mask = (1 << cache->offset_bits) - 1;
    cache->index_mask = (1 << cache->index_bits) - 1;
    
    // 分配 sets
    cache->sets = (CacheSet*)malloc(cache->num_sets * sizeof(CacheSet));
    for (uint32_t i = 0; i < cache->num_sets; i++) {
        cache->sets[i].lines = (CacheLine*)calloc(config->num_ways, sizeof(CacheLine));
        cache->sets[i].fifo_next = 0;
    }
    
    cache_reset(cache);
    return cache;
}

void cache_destroy(Cache *cache) {
    if (!cache) return;
    for (uint32_t i = 0; i < cache->num_sets; i++) {
        free(cache->sets[i].lines);
    }
    free(cache->sets);
    free(cache);
}

void cache_reset(Cache *cache) {
    cache->access_count = 0;
    cache->hit_count = 0;
    cache->miss_count = 0;
    cache->compulsory_miss = 0;
    cache->capacity_miss = 0;
    cache->conflict_miss = 0;
    
    for (uint32_t i = 0; i < cache->num_sets; i++) {
        for (uint32_t j = 0; j < cache->config.num_ways; j++) {
            cache->sets[i].lines[j].valid = false;
            cache->sets[i].lines[j].tag = 0;
            cache->sets[i].lines[j].lru_counter = 0;
            cache->sets[i].lines[j].fifo_order = 0;
        }
        cache->sets[i].fifo_next = 0;
    }
}

// 地址分解
static void decompose_addr(Cache *cache, uint32_t addr, 
                           uint32_t *tag, uint32_t *index) {
    *index = (addr >> cache->offset_bits) & cache->index_mask;
    *tag = addr >> (cache->offset_bits + cache->index_bits);
}

// LRU 替换：找到 LRU 计数最大的 way
static uint32_t find_lru_victim(CacheSet *set, uint32_t num_ways) {
    uint32_t victim = 0;
    uint32_t max_counter = 0;
    for (uint32_t i = 0; i < num_ways; i++) {
        if (!set->lines[i].valid) return i;  // 优先选无效的
        if (set->lines[i].lru_counter > max_counter) {
            max_counter = set->lines[i].lru_counter;
            victim = i;
        }
    }
    return victim;
}

// 更新 LRU 计数器
static void update_lru(CacheSet *set, uint32_t num_ways, uint32_t accessed_way) {
    for (uint32_t i = 0; i < num_ways; i++) {
        if (set->lines[i].valid) {
            set->lines[i].lru_counter++;
        }
    }
    set->lines[accessed_way].lru_counter = 0;
}

// FIFO 替换
static uint32_t find_fifo_victim(CacheSet *set, uint32_t num_ways) {
    for (uint32_t i = 0; i < num_ways; i++) {
        if (!set->lines[i].valid) return i;
    }
    uint32_t victim = set->fifo_next;
    set->fifo_next = (set->fifo_next + 1) % num_ways;
    return victim;
}

// Random 替换
static uint32_t find_random_victim(CacheSet *set, uint32_t num_ways) {
    for (uint32_t i = 0; i < num_ways; i++) {
        if (!set->lines[i].valid) return i;
    }
    return rand() % num_ways;
}

bool cache_access(Cache *cache, uint32_t addr) {
    uint32_t tag, index;
    decompose_addr(cache, addr, &tag, &index);
    
    cache->access_count++;
    CacheSet *set = &cache->sets[index];
    
    // 查找是否命中
    for (uint32_t i = 0; i < cache->config.num_ways; i++) {
        if (set->lines[i].valid && set->lines[i].tag == tag) {
            // HIT
            cache->hit_count++;
            if (cache->config.replace_policy == 'L') {
                update_lru(set, cache->config.num_ways, i);
            }
            return true;
        }
    }
    
    // MISS
    cache->miss_count++;
    
    // 选择替换目标
    uint32_t victim;
    switch (cache->config.replace_policy) {
        case 'L': victim = find_lru_victim(set, cache->config.num_ways); break;
        case 'F': victim = find_fifo_victim(set, cache->config.num_ways); break;
        case 'R': victim = find_random_victim(set, cache->config.num_ways); break;
        default:  victim = find_lru_victim(set, cache->config.num_ways); break;
    }
    
    // 判断缺失类型
    if (!set->lines[victim].valid) {
        cache->compulsory_miss++;
    }
    // 注：精确区分 capacity/conflict miss 需要无限容量 cache 辅助
    
    // 填充 cache line
    set->lines[victim].valid = true;
    set->lines[victim].tag = tag;
    if (cache->config.replace_policy == 'L') {
        update_lru(set, cache->config.num_ways, victim);
    }
    
    return false;
}

void cache_print_stats(Cache *cache) {
    double hit_rate = (double)cache->hit_count / cache->access_count * 100.0;
    double miss_rate = 100.0 - hit_rate;
    
    printf("\n========== CacheSim Statistics ==========\n");
    printf("Configuration:\n");
    printf("  Total Size:     %u bytes (%u KB)\n", 
           cache->config.total_size, cache->config.total_size / 1024);
    printf("  Line Size:      %u bytes\n", cache->config.line_size);
    printf("  Associativity:  %u-way\n", cache->config.num_ways);
    printf("  Number of Sets: %u\n", cache->num_sets);
    printf("  Replace Policy: %c\n", cache->config.replace_policy);
    printf("\nAddress Decomposition (32-bit):\n");
    printf("  Tag:    [31:%u] (%u bits)\n", 
           cache->offset_bits + cache->index_bits, cache->tag_bits);
    printf("  Index:  [%u:%u] (%u bits)\n", 
           cache->offset_bits + cache->index_bits - 1, cache->offset_bits, cache->index_bits);
    printf("  Offset: [%u:0] (%u bits)\n", 
           cache->offset_bits - 1, cache->offset_bits);
    printf("\nPerformance:\n");
    printf("  Total Accesses: %lu\n", cache->access_count);
    printf("  Hits:           %lu\n", cache->hit_count);
    printf("  Misses:         %lu\n", cache->miss_count);
    printf("  Hit Rate:       %.4f%%\n", hit_rate);
    printf("  Miss Rate:      %.4f%%\n", miss_rate);
    printf("  Compulsory Miss: %lu\n", cache->compulsory_miss);
    printf("==========================================\n");
}

void cache_export_csv(Cache *cache, const char *filename) {
    FILE *fp = fopen(filename, "w");
    if (!fp) {
        fprintf(stderr, "Error: Cannot open %s for writing\n", filename);
        return;
    }
    
    fprintf(fp, "total_size,line_size,num_ways,replace_policy,");
    fprintf(fp, "access_count,hit_count,miss_count,hit_rate,miss_rate\n");
    
    double hit_rate = (double)cache->hit_count / cache->access_count;
    fprintf(fp, "%u,%u,%u,%c,%lu,%lu,%lu,%.6f,%.6f\n",
            cache->config.total_size,
            cache->config.line_size,
            cache->config.num_ways,
            cache->config.replace_policy,
            cache->access_count,
            cache->hit_count,
            cache->miss_count,
            hit_rate,
            1.0 - hit_rate);
    
    fclose(fp);
}
```

### 步骤 3：实现 Trace 解析

**文件**：`tools/cachesim/src/trace.h`

```c
#ifndef TRACE_H
#define TRACE_H

#include <stdint.h>
#include <stdio.h>

// Trace 文件格式支持
typedef enum {
    TRACE_FORMAT_TEXT,      // 每行一个十六进制 PC
    TRACE_FORMAT_BINARY,    // 二进制 PC 序列
    TRACE_FORMAT_COMPRESSED // bzip2 压缩
} TraceFormat;

typedef struct {
    FILE       *fp;
    TraceFormat format;
    uint64_t    count;      // 已读取的 PC 数量
} TraceReader;

TraceReader* trace_open(const char *filename, TraceFormat format);
void         trace_close(TraceReader *reader);
int          trace_read_pc(TraceReader *reader, uint32_t *pc);  // 返回 1 成功，0 结束，-1 错误
uint64_t     trace_get_count(TraceReader *reader);

#endif
```

**文件**：`tools/cachesim/src/trace.c`

```c
#include "trace.h"
#include <stdlib.h>
#include <string.h>

TraceReader* trace_open(const char *filename, TraceFormat format) {
    TraceReader *reader = (TraceReader*)malloc(sizeof(TraceReader));
    if (!reader) return NULL;
    
    reader->format = format;
    reader->count = 0;
    
    if (format == TRACE_FORMAT_COMPRESSED) {
        // 使用 popen 解压缩
        char cmd[512];
        snprintf(cmd, sizeof(cmd), "bzcat %s", filename);
        reader->fp = popen(cmd, "r");
    } else {
        reader->fp = fopen(filename, format == TRACE_FORMAT_BINARY ? "rb" : "r");
    }
    
    if (!reader->fp) {
        free(reader);
        return NULL;
    }
    
    return reader;
}

void trace_close(TraceReader *reader) {
    if (!reader) return;
    if (reader->format == TRACE_FORMAT_COMPRESSED) {
        pclose(reader->fp);
    } else {
        fclose(reader->fp);
    }
    free(reader);
}

int trace_read_pc(TraceReader *reader, uint32_t *pc) {
    if (!reader || !reader->fp) return -1;
    
    int result;
    switch (reader->format) {
        case TRACE_FORMAT_TEXT:
            result = fscanf(reader->fp, "%x", pc);
            if (result == 1) {
                reader->count++;
                return 1;
            }
            return result == EOF ? 0 : -1;
            
        case TRACE_FORMAT_BINARY:
        case TRACE_FORMAT_COMPRESSED:
            result = fread(pc, sizeof(uint32_t), 1, reader->fp);
            if (result == 1) {
                reader->count++;
                return 1;
            }
            return feof(reader->fp) ? 0 : -1;
            
        default:
            return -1;
    }
}

uint64_t trace_get_count(TraceReader *reader) {
    return reader ? reader->count : 0;
}
```

### 步骤 4：实现主程序

**文件**：`tools/cachesim/src/main.c`

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <time.h>
#include "cache.h"
#include "trace.h"

static void print_usage(const char *prog) {
    printf("Usage: %s [options] <trace_file>\n", prog);
    printf("\nOptions:\n");
    printf("  -s, --size <bytes>     Cache total size (default: 4096)\n");
    printf("  -l, --line <bytes>     Cache line size (default: 4)\n");
    printf("  -w, --ways <num>       Associativity (default: 2)\n");
    printf("  -r, --replace <L|F|R>  Replacement policy (default: L)\n");
    printf("                         L=LRU, F=FIFO, R=Random\n");
    printf("  -f, --format <t|b|c>   Trace format (default: t)\n");
    printf("                         t=text, b=binary, c=compressed(bz2)\n");
    printf("  -o, --output <file>    Export CSV to file\n");
    printf("  -p, --penalty <cycles> Miss penalty for TMT calculation\n");
    printf("  -q, --quiet            Quiet mode, only output result line\n");
    printf("  -h, --help             Show this help\n");
    printf("\nExamples:\n");
    printf("  %s -s 4096 -l 16 -w 4 trace.txt\n", prog);
    printf("  %s -s 8192 -l 32 -w 8 -r F -f b trace.bin\n", prog);
}

int main(int argc, char *argv[]) {
    // 默认配置
    CacheConfig config = {
        .total_size = 4096,
        .line_size = 4,
        .num_ways = 2,
        .replace_policy = 'L'
    };
    
    TraceFormat trace_format = TRACE_FORMAT_TEXT;
    const char *output_file = NULL;
    uint32_t miss_penalty = 0;
    int quiet = 0;
    
    // 解析命令行参数
    static struct option long_options[] = {
        {"size",    required_argument, 0, 's'},
        {"line",    required_argument, 0, 'l'},
        {"ways",    required_argument, 0, 'w'},
        {"replace", required_argument, 0, 'r'},
        {"format",  required_argument, 0, 'f'},
        {"output",  required_argument, 0, 'o'},
        {"penalty", required_argument, 0, 'p'},
        {"quiet",   no_argument,       0, 'q'},
        {"help",    no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "s:l:w:r:f:o:p:qh", long_options, NULL)) != -1) {
        switch (opt) {
            case 's': config.total_size = atoi(optarg); break;
            case 'l': config.line_size = atoi(optarg); break;
            case 'w': config.num_ways = atoi(optarg); break;
            case 'r': config.replace_policy = optarg[0]; break;
            case 'f':
                switch (optarg[0]) {
                    case 't': trace_format = TRACE_FORMAT_TEXT; break;
                    case 'b': trace_format = TRACE_FORMAT_BINARY; break;
                    case 'c': trace_format = TRACE_FORMAT_COMPRESSED; break;
                }
                break;
            case 'o': output_file = optarg; break;
            case 'p': miss_penalty = atoi(optarg); break;
            case 'q': quiet = 1; break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    if (optind >= argc) {
        fprintf(stderr, "Error: No trace file specified\n");
        print_usage(argv[0]);
        return 1;
    }
    
    const char *trace_file = argv[optind];
    
    // 参数验证
    if (config.total_size == 0 || (config.total_size & (config.total_size - 1)) != 0) {
        fprintf(stderr, "Error: total_size must be power of 2\n");
        return 1;
    }
    if (config.line_size == 0 || (config.line_size & (config.line_size - 1)) != 0) {
        fprintf(stderr, "Error: line_size must be power of 2\n");
        return 1;
    }
    if (config.num_ways == 0 || (config.num_ways & (config.num_ways - 1)) != 0) {
        fprintf(stderr, "Error: num_ways must be power of 2\n");
        return 1;
    }
    
    // 创建 cache
    Cache *cache = cache_create(&config);
    if (!cache) {
        fprintf(stderr, "Error: Failed to create cache\n");
        return 1;
    }
    
    // 打开 trace 文件
    TraceReader *reader = trace_open(trace_file, trace_format);
    if (!reader) {
        fprintf(stderr, "Error: Failed to open trace file: %s\n", trace_file);
        cache_destroy(cache);
        return 1;
    }
    
    // 模拟执行
    if (!quiet) {
        printf("Simulating cache with %s...\n", trace_file);
    }
    
    clock_t start = clock();
    uint32_t pc;
    while (trace_read_pc(reader, &pc) == 1) {
        cache_access(cache, pc);
    }
    clock_t end = clock();
    
    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    
    // 输出结果
    if (quiet) {
        // 简洁输出：size,line,ways,policy,accesses,hits,misses,hit_rate,tmt
        uint64_t tmt = cache->miss_count * miss_penalty;
        printf("%u,%u,%u,%c,%lu,%lu,%lu,%.6f,%lu\n",
               config.total_size, config.line_size, config.num_ways,
               config.replace_policy,
               cache->access_count, cache->hit_count, cache->miss_count,
               (double)cache->hit_count / cache->access_count,
               tmt);
    } else {
        cache_print_stats(cache);
        printf("\nSimulation completed in %.3f seconds\n", elapsed);
        printf("Throughput: %.2f M accesses/sec\n", 
               cache->access_count / elapsed / 1000000.0);
        
        if (miss_penalty > 0) {
            uint64_t tmt = cache->miss_count * miss_penalty;
            printf("\nTMT Estimation (miss_penalty = %u cycles):\n", miss_penalty);
            printf("  Total Miss Time: %lu cycles\n", tmt);
            printf("  Avg Miss Time per Access: %.2f cycles\n",
                   (double)tmt / cache->access_count);
        }
    }
    
    // 导出 CSV
    if (output_file) {
        cache_export_csv(cache, output_file);
        if (!quiet) {
            printf("\nResults exported to %s\n", output_file);
        }
    }
    
    trace_close(reader);
    cache_destroy(cache);
    return 0;
}
```

### 步骤 5：编写 Makefile

**文件**：`tools/cachesim/Makefile`

```makefile
CC = gcc
CFLAGS = -O3 -Wall -Wextra -std=c99
LDFLAGS = -lm

SRC_DIR = src
BUILD_DIR = build
BIN = cachesim

SRCS = $(wildcard $(SRC_DIR)/*.c)
OBJS = $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SRCS))

.PHONY: all clean test

all: $(BIN)

$(BIN): $(OBJS)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(BIN)

test: $(BIN)
	./test/run_tests.sh
```

### 步骤 6：修改 NEMU 输出简化 itrace

在 NEMU 中添加选项，输出纯 PC 序列。

**修改文件**：`nemu/src/cpu/cpu-exec.c`

添加配置选项 `CONFIG_ITRACE_PC_ONLY`：

```c
#ifdef CONFIG_ITRACE_PC_ONLY
    // 只输出 PC（十六进制或二进制）
    #ifdef CONFIG_ITRACE_BINARY
        fwrite(&s->pc, sizeof(uint32_t), 1, log_fp);
    #else
        log_write(FMT_WORD "\n", s->pc);
    #endif
#else
    // 原有完整 itrace 输出
    // ...
#endif
```

**修改文件**：`nemu/Kconfig`

```
config ITRACE_PC_ONLY
  bool "Output PC only in itrace (for cachesim)"
  default n
  depends on ITRACE

config ITRACE_BINARY
  bool "Output itrace in binary format"
  default n
  depends on ITRACE_PC_ONLY
```

## 批量评估脚本

**文件**：`tools/cachesim/scripts/dse.sh`

```bash
#!/bin/bash

# 设计空间探索脚本
CACHESIM=./cachesim
TRACE=$1
OUTPUT=dse_results.csv
MISS_PENALTY=${2:-70}  # 默认缺失代价

if [ -z "$TRACE" ]; then
    echo "Usage: $0 <trace_file> [miss_penalty]"
    exit 1
fi

# 参数空间
SIZES="2048 4096 8192 16384"
LINES="4 8 16 32"
WAYS="1 2 4 8"
POLICIES="L F R"

echo "size,line,ways,policy,accesses,hits,misses,hit_rate,tmt" > $OUTPUT

for size in $SIZES; do
    for line in $LINES; do
        for way in $WAYS; do
            for policy in $POLICIES; do
                # 检查参数有效性
                num_sets=$((size / line / way))
                if [ $num_sets -lt 1 ]; then
                    continue
                fi
                
                $CACHESIM -s $size -l $line -w $way -r $policy \
                         -p $MISS_PENALTY -q "$TRACE" >> $OUTPUT
            done
        done
    done
done

echo "Results saved to $OUTPUT"
echo "Top 10 configurations by hit rate:"
sort -t',' -k8 -rn $OUTPUT | head -11
```

**文件**：`tools/cachesim/scripts/parallel_dse.sh`

```bash
#!/bin/bash

# 并行设计空间探索
CACHESIM=./cachesim
TRACE=$1
OUTPUT_DIR=dse_output
MISS_PENALTY=${2:-70}
NUM_CORES=${3:-$(nproc)}

if [ -z "$TRACE" ]; then
    echo "Usage: $0 <trace_file> [miss_penalty] [num_cores]"
    exit 1
fi

mkdir -p $OUTPUT_DIR

# 生成所有配置
configs=()
for size in 2048 4096 8192 16384; do
    for line in 4 8 16 32; do
        for way in 1 2 4 8; do
            for policy in L F R; do
                num_sets=$((size / line / way))
                if [ $num_sets -ge 1 ]; then
                    configs+=("$size,$line,$way,$policy")
                fi
            done
        done
    done
done

echo "Total configurations: ${#configs[@]}"
echo "Running with $NUM_CORES parallel jobs..."

# 并行执行
run_config() {
    IFS=',' read -r size line way policy <<< "$1"
    $CACHESIM -s $size -l $line -w $way -r $policy \
             -p $MISS_PENALTY -q "$TRACE"
}
export -f run_config
export CACHESIM TRACE MISS_PENALTY

printf '%s\n' "${configs[@]}" | xargs -P $NUM_CORES -I {} bash -c 'run_config "$@"' _ {} \
    > $OUTPUT_DIR/results.csv

echo "size,line,ways,policy,accesses,hits,misses,hit_rate,tmt" > $OUTPUT_DIR/final_results.csv
cat $OUTPUT_DIR/results.csv >> $OUTPUT_DIR/final_results.csv

echo "Results saved to $OUTPUT_DIR/final_results.csv"
```

## 验收标准

1. [ ] cachesim 编译无警告
2. [ ] 支持文本、二进制、压缩三种 trace 格式
3. [ ] 支持 LRU、FIFO、Random 三种替换策略
4. [ ] 参数化配置：容量、块大小、路数
5. [ ] 输出命中率、缺失次数、TMT 估算
6. [ ] 与 NPC ICache 性能计数器结果一致（对相同 PC 序列）
7. [ ] 批量评估脚本正常工作

## 一致性验证

为确保 cachesim 与 RTL 实现一致：

1. 在 NPC 运行程序，记录性能计数器
2. 用 NEMU 生成相同程序的 PC trace
3. 用相同参数运行 cachesim
4. 比较 `miss_count` 是否一致

```bash
# NPC 运行
make -C npc ARCH=riscv32e-ysyxsoc run
# 记录 miss_count

# 生成 trace
make -C nemu ARCH=riscv32e-nemu run ARGS="-l trace.txt"

# cachesim 验证
./cachesim -s 4096 -l 4 -w 2 -r L trace.txt
# 比较 miss_count
```

## 相关文件

| 文件 | 说明 |
|------|------|
| `tools/cachesim/` | cachesim 实现目录 |
| `nemu/src/cpu/cpu-exec.c` | NEMU itrace 输出修改 |
| `nemu/Kconfig` | NEMU 配置选项 |

## 预计工作量

- cachesim 核心实现：4-6 小时
- NEMU itrace 修改：1-2 小时
- 测试和验证：2-3 小时
- 批量评估脚本：1-2 小时
