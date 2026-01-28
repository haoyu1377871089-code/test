# 阶段一：AMAT 统计实现计划

## 任务目标

在 NPC 中添加完善的性能计数器，准确统计 ICache 的 AMAT（Average Memory Access Time）。

## 背景知识

AMAT 计算公式：
```
AMAT = p * access_time + (1 - p) * (access_time + miss_penalty)
     = access_time + (1 - p) * miss_penalty
```

其中：
- `p`：命中率 = hit_count / (hit_count + miss_count)
- `access_time`：cache 访问时间（从接收请求到得出命中结果的周期数）
- `miss_penalty`：缺失代价（访问下一级存储的时间）

## 当前状态分析

### 已有性能计数器

位置：`npc/vsrc/core/ICache.v`

```verilog
`ifdef SIMULATION
    reg [63:0] perf_icache_hit_cnt;        // 命中次数
    reg [63:0] perf_icache_miss_cnt;       // 缺失次数
    reg [63:0] perf_icache_refill_cycles;  // refill 总周期数
    reg [31:0] refill_cycle_counter;       // 单次 refill 计数器
`endif
```

### 缺失项

1. 总访问周期数统计（用于计算 access_time）
2. AMAT 计算和输出
3. 更细粒度的延迟分解统计

## 实现规范

### 步骤 1：分析 ICache 时序

**任务**：确定当前 ICache 的 access_time

根据状态机分析：
- IDLE → LOOKUP：1 周期（捕获地址）
- LOOKUP 状态下判断命中：组合逻辑，同周期完成
- 命中时：LOOKUP → IDLE，同周期返回数据

**结论**：access_time = 2 周期（从 cpu_req 有效到 cpu_rvalid 有效）

**验证方法**：
1. 在仿真中观察 cache hit 情况下的波形
2. 记录从 `cpu_req` 上升沿到 `cpu_rvalid` 上升沿的周期数

### 步骤 2：添加性能计数器

在 `ICache.v` 中添加以下计数器：

```verilog
`ifdef SIMULATION
    // 基础计数器（已有）
    reg [63:0] perf_icache_hit_cnt;
    reg [63:0] perf_icache_miss_cnt;
    reg [63:0] perf_icache_refill_cycles;
    
    // 新增计数器
    reg [63:0] perf_icache_total_cycles;     // 总访问周期数
    reg [63:0] perf_icache_access_cnt;       // 总访问次数
    reg [31:0] access_cycle_counter;         // 单次访问计数器
    
    // 延迟分解统计
    reg [63:0] perf_refill_ar_cycles;        // AR 通道等待周期
    reg [63:0] perf_refill_r_cycles;         // R 通道等待周期
`endif
```

### 步骤 3：实现计数逻辑

**访问周期统计**：

```verilog
always @(posedge clk or posedge rst) begin
    if (rst) begin
        perf_icache_total_cycles <= 64'd0;
        perf_icache_access_cnt <= 64'd0;
        access_cycle_counter <= 32'd0;
    end else begin
        case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    access_cycle_counter <= 32'd1;
                end
            end
            S_LOOKUP, S_REFILL: begin
                access_cycle_counter <= access_cycle_counter + 1;
                if (cpu_rvalid) begin
                    perf_icache_total_cycles <= perf_icache_total_cycles + 
                                                {32'b0, access_cycle_counter};
                    perf_icache_access_cnt <= perf_icache_access_cnt + 1;
                end
            end
        endcase
    end
end
```

### 步骤 4：计算并输出 AMAT

在顶层模块 `ysyx_00000000.v` 的 `$finish` 前添加统计输出：

```verilog
`ifdef SIMULATION
    // 在仿真结束时输出
    real hit_rate;
    real avg_access_time;
    real avg_miss_penalty;
    real amat;
    
    initial begin
        // ... 原有代码 ...
    end
    
    // 添加统计输出任务
    task print_cache_stats;
        begin
            if (icache_inst.perf_icache_access_cnt > 0) begin
                hit_rate = $itor(icache_inst.perf_icache_hit_cnt) / 
                          $itor(icache_inst.perf_icache_access_cnt);
                
                avg_access_time = $itor(icache_inst.perf_icache_total_cycles) /
                                 $itor(icache_inst.perf_icache_access_cnt);
                
                if (icache_inst.perf_icache_miss_cnt > 0) begin
                    avg_miss_penalty = $itor(icache_inst.perf_icache_refill_cycles) /
                                      $itor(icache_inst.perf_icache_miss_cnt);
                end else begin
                    avg_miss_penalty = 0.0;
                end
                
                // AMAT = access_time + (1-p) * miss_penalty
                // 但由于 hit 时 access_time 较小，miss 时包含 refill
                // 实际 AMAT = total_cycles / access_cnt
                amat = avg_access_time;
                
                $display("========== ICache Performance Statistics ==========");
                $display("Total Accesses:     %d", icache_inst.perf_icache_access_cnt);
                $display("Hits:               %d", icache_inst.perf_icache_hit_cnt);
                $display("Misses:             %d", icache_inst.perf_icache_miss_cnt);
                $display("Hit Rate:           %.4f%%", hit_rate * 100.0);
                $display("Avg Access Time:    %.2f cycles", avg_access_time);
                $display("Avg Miss Penalty:   %.2f cycles", avg_miss_penalty);
                $display("AMAT:               %.2f cycles", amat);
                $display("Total Refill Cycles: %d", icache_inst.perf_icache_refill_cycles);
                $display("===================================================");
            end
        end
    endtask
`endif
```

### 步骤 5：验证实现

**测试用例**：

1. **冷启动测试**：
   - 运行简短程序，验证首次访问全部 miss
   - 预期：miss_count ≈ 指令数（考虑循环）

2. **热点循环测试**：
   - 运行包含紧凑循环的程序
   - 预期：hit_rate 应较高

3. **数据一致性验证**：
   - 验证 `hit_count + miss_count == access_count`
   - 验证 `total_cycles >= access_count * 2`（最小 2 周期）

**验证命令**：
```bash
cd npc
make ARCH=riscv32e-ysyxsoc run
# 观察输出的性能统计
```

## 输出规范

### 性能报告格式

```
========== ICache Performance Statistics ==========
Total Accesses:     1000000
Hits:               950000
Misses:             50000
Hit Rate:           95.0000%
Avg Access Time:    5.50 cycles
Avg Miss Penalty:   70.00 cycles
AMAT:               5.50 cycles
Total Refill Cycles: 3500000
===================================================
```

### 数据导出

为便于后续分析，添加 CSV 格式导出：

```verilog
task export_cache_stats_csv;
    integer fd;
    begin
        fd = $fopen("cache_stats.csv", "w");
        $fwrite(fd, "metric,value\n");
        $fwrite(fd, "access_count,%d\n", icache_inst.perf_icache_access_cnt);
        $fwrite(fd, "hit_count,%d\n", icache_inst.perf_icache_hit_cnt);
        $fwrite(fd, "miss_count,%d\n", icache_inst.perf_icache_miss_cnt);
        $fwrite(fd, "total_cycles,%d\n", icache_inst.perf_icache_total_cycles);
        $fwrite(fd, "refill_cycles,%d\n", icache_inst.perf_icache_refill_cycles);
        $fclose(fd);
    end
endtask
```

## 验收标准

1. [ ] 所有计数器在复位后初始化为 0
2. [ ] hit_count + miss_count == access_count
3. [ ] AMAT 计算结果合理（hit_rate 高时接近 2 周期，低时接近 miss_penalty）
4. [ ] 通过 microbench test 规模测试
5. [ ] 性能统计输出格式正确

## 相关文件

| 文件 | 说明 |
|------|------|
| `npc/vsrc/core/ICache.v` | ICache 实现，添加计数器 |
| `npc/vsrc/ysyx_00000000.v` | 顶层模块，添加统计输出 |
| `cache_stats.csv` | 性能数据导出文件 |

## 预计工作量

- 代码修改：2-3 小时
- 验证测试：1-2 小时
- 文档整理：1 小时
