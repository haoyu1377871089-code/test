# 阶段三：扩展 Cache Line 与突发传输实现计划

## 任务目标

1. 将 ICache 的 cache line 从 4 字节扩展到 16/32 字节
2. 实现 AXI4 突发传输以高效填充更大的 cache line
3. 切换到 AXI 接口的 SDRAM 控制器
4. 实现 AXI4 延迟模块进行访存延迟校准

## 背景分析

### 当前状态

| 项目 | 当前值 | 目标值 |
|------|--------|--------|
| Cache Line 大小 | 4B | 16B/32B |
| 总线接口 | AXI4-Lite | AXI4 (支持 burst) |
| SDRAM 接口 | APB | AXI4 |
| AXI4 延迟模块 | 透传 | 完整实现 |

### 突发传输收益分析

假设 SDRAM 访问时间模型：
```
单次传输开销 = a + b + c + d
  a: AR 通道握手时间
  b: 状态机转移时间  
  c: SDRAM 颗粒响应时间
  d: R 通道握手时间
```

对于 16 字节 cache line（4 次传输）：
- 独立传输方式：4 × (a + b + c + d)
- 突发传输方式：a + b + 4c + d

节省开销：3 × (a + b + d)

## 实现规范

---

## Part A：扩展 Cache Line 大小

### 步骤 A1：修改 ICache 参数

**文件**：`npc/vsrc/core/ICache.v`

```verilog
// 参数化设计
module ICache #(
    parameter CACHE_SIZE    = 4096,     // 总容量（字节）
    parameter LINE_SIZE     = 16,       // cache line 大小（字节）
    parameter NUM_WAYS      = 2,        // 组相联路数
    parameter ADDR_WIDTH    = 32
) (
    input clk,
    input rst,
    
    // CPU 接口（不变）
    input               cpu_req,
    input  [31:0]       cpu_addr,
    output reg          cpu_rvalid,
    output reg [31:0]   cpu_rdata,
    
    // 内存接口（新增突发支持）
    output reg          mem_req,
    output reg [31:0]   mem_addr,
    output reg [7:0]    mem_len,        // 突发长度 (0=1拍, 3=4拍)
    input               mem_rvalid,
    input      [31:0]   mem_rdata,
    input               mem_rlast       // 突发传输最后一拍
);

// 计算派生参数
localparam OFFSET_WIDTH = $clog2(LINE_SIZE);
localparam NUM_SETS     = CACHE_SIZE / LINE_SIZE / NUM_WAYS;
localparam INDEX_WIDTH  = $clog2(NUM_SETS);
localparam TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;
localparam WORDS_PER_LINE = LINE_SIZE / 4;  // 每 line 的字数
```

### 步骤 A2：修改存储结构

```verilog
// Cache 存储（参数化）
// Valid bits: [way][set]
reg valid [0:NUM_WAYS-1][0:NUM_SETS-1];

// Tags: [way][set]
reg [TAG_WIDTH-1:0] tags [0:NUM_WAYS-1][0:NUM_SETS-1];

// Data: [way][set][word] - 多字 cache line
reg [31:0] data [0:NUM_WAYS-1][0:NUM_SETS-1][0:WORDS_PER_LINE-1];

// LRU bits
reg [NUM_WAYS-2:0] lru [0:NUM_SETS-1];  // 树形 LRU（多路时）
```

### 步骤 A3：修改地址分解

```verilog
// 地址分解
wire [TAG_WIDTH-1:0]    req_tag    = req_addr_reg[ADDR_WIDTH-1 -: TAG_WIDTH];
wire [INDEX_WIDTH-1:0]  req_index  = req_addr_reg[OFFSET_WIDTH +: INDEX_WIDTH];
wire [OFFSET_WIDTH-1:0] req_offset = req_addr_reg[OFFSET_WIDTH-1:0];
wire [$clog2(WORDS_PER_LINE)-1:0] req_word = req_addr_reg[OFFSET_WIDTH-1:2];
```

### 步骤 A4：修改命中逻辑

```verilog
// 命中判断
wire hit_way0 = valid[0][req_index] && (tags[0][req_index] == req_tag);
wire hit_way1 = valid[1][req_index] && (tags[1][req_index] == req_tag);
wire cache_hit = hit_way0 || hit_way1;

// 命中时选择正确的字
wire [31:0] hit_data_way0 = data[0][req_index][req_word];
wire [31:0] hit_data_way1 = data[1][req_index][req_word];
```

### 步骤 A5：修改 Refill 状态机

```verilog
// Refill 状态
localparam S_IDLE       = 3'd0;
localparam S_LOOKUP     = 3'd1;
localparam S_REFILL_REQ = 3'd2;  // 发送突发请求
localparam S_REFILL_DATA= 3'd3;  // 接收突发数据

reg [2:0] state;
reg [$clog2(WORDS_PER_LINE)-1:0] refill_word_cnt;  // 当前接收的字索引
reg [INDEX_WIDTH-1:0] refill_index;
reg [TAG_WIDTH-1:0]   refill_tag;
reg                   refill_way;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        // ... 初始化
    end else begin
        case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    req_addr_reg <= cpu_addr;
                    state <= S_LOOKUP;
                end
            end
            
            S_LOOKUP: begin
                if (cache_hit) begin
                    cpu_rvalid <= 1'b1;
                    cpu_rdata <= hit_way0 ? hit_data_way0 : hit_data_way1;
                    // 更新 LRU
                    state <= S_IDLE;
                end else begin
                    // Miss - 准备 refill
                    refill_index <= req_index;
                    refill_tag <= req_tag;
                    refill_way <= lru[req_index][0];  // 简化 LRU
                    refill_word_cnt <= 0;
                    state <= S_REFILL_REQ;
                end
            end
            
            S_REFILL_REQ: begin
                // 发送突发读请求
                mem_req <= 1'b1;
                mem_addr <= {req_addr_reg[31:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
                mem_len <= WORDS_PER_LINE - 1;  // 突发长度
                state <= S_REFILL_DATA;
            end
            
            S_REFILL_DATA: begin
                mem_req <= 1'b0;
                if (mem_rvalid) begin
                    // 写入 cache line 的对应字
                    data[refill_way][refill_index][refill_word_cnt] <= mem_rdata;
                    refill_word_cnt <= refill_word_cnt + 1;
                    
                    if (mem_rlast) begin
                        // 突发传输完成
                        valid[refill_way][refill_index] <= 1'b1;
                        tags[refill_way][refill_index] <= refill_tag;
                        
                        // 返回请求的字
                        cpu_rvalid <= 1'b1;
                        cpu_rdata <= (refill_word_cnt == req_word) ? 
                                     mem_rdata : 
                                     data[refill_way][refill_index][req_word];
                        
                        // 更新 LRU
                        lru[refill_index] <= ~refill_way;
                        state <= S_IDLE;
                    end
                end
            end
        endcase
    end
end
```

### 步骤 A6：Critical Word First 优化（可选）

为减少 miss penalty，可以先返回请求的字，再填充剩余字：

```verilog
// Critical Word First: 先请求包含目标字的地址
// 然后 wrap around 填充剩余字

reg [$clog2(WORDS_PER_LINE)-1:0] critical_word;
reg                              critical_word_returned;

// 在 S_REFILL_REQ 时设置起始地址为包含目标字的地址
// 使用 WRAP burst 模式
```

---

## Part B：实现 AXI4 突发传输

### 步骤 B1：创建新的 IFU_AXI4 模块

**文件**：`npc/vsrc/core/IFU_AXI4.v`

```verilog
// AXI4 Master with Burst Support for ICache
module IFU_AXI4 (
    input clk,
    input rst,
    
    // ICache 接口
    input               icache_req,
    input      [31:0]   icache_addr,
    input      [7:0]    icache_len,     // 突发长度
    output reg          icache_rvalid,
    output reg [31:0]   icache_rdata,
    output reg          icache_rlast,
    
    // AXI4 Master 接口 - AR 通道
    output reg          m_axi_arvalid,
    input               m_axi_arready,
    output reg [31:0]   m_axi_araddr,
    output reg [7:0]    m_axi_arlen,    // 突发长度 (实际传输数 = arlen + 1)
    output reg [2:0]    m_axi_arsize,   // 每次传输大小 (2 = 4 bytes)
    output reg [1:0]    m_axi_arburst,  // 突发类型 (1 = INCR)
    output     [3:0]    m_axi_arid,
    output     [3:0]    m_axi_arcache,
    output     [2:0]    m_axi_arprot,
    
    // AXI4 Master 接口 - R 通道
    input               m_axi_rvalid,
    output reg          m_axi_rready,
    input      [31:0]   m_axi_rdata,
    input      [1:0]    m_axi_rresp,
    input               m_axi_rlast,
    input      [3:0]    m_axi_rid
);

// 固定信号
assign m_axi_arid    = 4'b0;
assign m_axi_arcache = 4'b0011;  // Normal Non-cacheable Bufferable
assign m_axi_arprot  = 3'b000;

// 状态机
localparam S_IDLE    = 2'd0;
localparam S_AR      = 2'd1;  // 等待 AR 握手
localparam S_R       = 2'd2;  // 接收 R 数据

reg [1:0] state;
reg [7:0] beat_count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
        icache_rvalid <= 1'b0;
        icache_rlast <= 1'b0;
        beat_count <= 8'd0;
    end else begin
        // 默认清除
        icache_rvalid <= 1'b0;
        icache_rlast <= 1'b0;
        
        case (state)
            S_IDLE: begin
                if (icache_req) begin
                    // 发起 AR 请求
                    m_axi_arvalid <= 1'b1;
                    m_axi_araddr <= icache_addr;
                    m_axi_arlen <= icache_len;
                    m_axi_arsize <= 3'b010;   // 4 bytes
                    m_axi_arburst <= 2'b01;   // INCR
                    beat_count <= 8'd0;
                    state <= S_AR;
                end
            end
            
            S_AR: begin
                if (m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;
                    state <= S_R;
                end
            end
            
            S_R: begin
                if (m_axi_rvalid) begin
                    // 收到数据
                    icache_rvalid <= 1'b1;
                    icache_rdata <= m_axi_rdata;
                    beat_count <= beat_count + 1;
                    
                    if (m_axi_rlast) begin
                        // 突发传输结束
                        icache_rlast <= 1'b1;
                        m_axi_rready <= 1'b0;
                        state <= S_IDLE;
                    end
                end
            end
        endcase
    end
end

endmodule
```

### 步骤 B2：修改 AXI 仲裁器

**文件**：`npc/vsrc/core/AXI4_Arbiter.v`

需要支持完整的 AXI4 信号，包括 `arlen`, `arburst` 等：

```verilog
// 新增端口
input  [7:0]  ifu_arlen,
input  [1:0]  ifu_arburst,
input  [7:0]  lsu_arlen,
input  [1:0]  lsu_arburst,
output [7:0]  m_arlen,
output [1:0]  m_arburst,

// 仲裁逻辑中转发这些信号
assign m_arlen   = ifu_grant ? ifu_arlen   : lsu_arlen;
assign m_arburst = ifu_grant ? ifu_arburst : lsu_arburst;
```

### 步骤 B3：移除 AXI4-Lite 到 AXI4 桥接

当使用完整 AXI4 时，`AXI4_Lite_to_AXI4_Bridge.v` 不再需要，直接连接到 SoC。

---

## Part C：切换到 AXI 接口 SDRAM

### 步骤 C1：修改 ysyxSoC 配置

**文件**：`ysyxSoC/src/Top.scala`

```scala
object Config {
  def hasChipLink: Boolean = false
  def sdramUseAXI: Boolean = true  // 改为 true
}
```

### 步骤 C2：重新生成 SoC

```bash
cd ysyxSoC
make verilog
# 生成新的 ysyxSoCFull.v
```

### 步骤 C3：验证基本功能

```bash
cd npc
make ARCH=riscv32e-ysyxsoc run
# 验证程序能正常运行
```

---

## Part D：实现 AXI4 延迟模块

### 步骤 D1：设计延迟校准逻辑

**延迟校准原理**：

设 CPU 频率为 `f_cpu`，设备频率为 `f_dev`，频率比 `r = f_cpu / f_dev`。

对于读事务的第 i 个 beat：
- 设备端返回时间：`t_i`（相对于事务开始 `t_0`）
- CPU 端感知时间：`t_i' = t_0 + (t_i - t_0) * r`

### 步骤 D2：实现 AXI4 延迟模块

**文件**：`ysyxSoC/perip/amba/axi4_delayer.v`

```verilog
module axi4_delayer #(
    parameter R_TIMES_S = 1024,  // r * s，其中 s = 2^S_SHIFT
    parameter S_SHIFT   = 8,    // s = 256
    parameter MAX_BURST = 8     // 最大突发长度
)(
    input         clock,
    input         reset,
    
    // 上游接口（连接 CPU）
    output reg    in_arready,
    input         in_arvalid,
    input  [3:0]  in_arid,
    input  [31:0] in_araddr,
    input  [7:0]  in_arlen,
    input  [2:0]  in_arsize,
    input  [1:0]  in_arburst,
    input         in_rready,
    output reg    in_rvalid,
    output [3:0]  in_rid,
    output [31:0] in_rdata,
    output [1:0]  in_rresp,
    output        in_rlast,
    
    // 下游接口（连接设备）
    input         out_arready,
    output reg    out_arvalid,
    output [3:0]  out_arid,
    output [31:0] out_araddr,
    output [7:0]  out_arlen,
    output [2:0]  out_arsize,
    output [1:0]  out_arburst,
    output reg    out_rready,
    input         out_rvalid,
    input  [3:0]  out_rid,
    input  [31:0] out_rdata,
    input  [1:0]  out_rresp,
    input         out_rlast,
    
    // 写通道（类似处理，此处省略）
    // ...
);

// ================================================================
// 读通道延迟处理
// ================================================================

// 状态
localparam R_IDLE      = 2'd0;
localparam R_WAIT_DEV  = 2'd1;  // 等待设备响应
localparam R_DELAY     = 2'd2;  // 延迟倒计时

reg [1:0] r_state;

// 事务信息保存
reg [3:0]  saved_arid;
reg [31:0] saved_araddr;
reg [7:0]  saved_arlen;
reg [2:0]  saved_arsize;
reg [1:0]  saved_arburst;

// 每个 beat 的信息缓存
reg [31:0] beat_data   [0:MAX_BURST-1];
reg [1:0]  beat_resp   [0:MAX_BURST-1];
reg        beat_last   [0:MAX_BURST-1];
reg [31:0] beat_target [0:MAX_BURST-1];  // 目标延迟时间

reg [3:0]  beat_recv_cnt;   // 已接收 beat 数
reg [3:0]  beat_send_cnt;   // 已发送 beat 数
reg [31:0] dev_cycle_cnt;   // 设备周期计数
reg [31:0] cpu_cycle_cnt;   // CPU 周期计数
reg [31:0] delay_counter;   // 当前延迟计数器

// 透传信号
assign out_arid    = saved_arid;
assign out_araddr  = saved_araddr;
assign out_arlen   = saved_arlen;
assign out_arsize  = saved_arsize;
assign out_arburst = saved_arburst;

assign in_rid   = saved_arid;
assign in_rdata = beat_data[beat_send_cnt];
assign in_rresp = beat_resp[beat_send_cnt];
assign in_rlast = beat_last[beat_send_cnt];

// 延迟计算函数
function [31:0] calc_delay;
    input [31:0] dev_time;
    begin
        // target_cpu_time = dev_time * r = dev_time * R_TIMES_S / s
        calc_delay = (dev_time * R_TIMES_S) >> S_SHIFT;
    end
endfunction

always @(posedge clock or posedge reset) begin
    if (reset) begin
        r_state <= R_IDLE;
        in_arready <= 1'b1;
        out_arvalid <= 1'b0;
        out_rready <= 1'b0;
        in_rvalid <= 1'b0;
        beat_recv_cnt <= 4'd0;
        beat_send_cnt <= 4'd0;
        dev_cycle_cnt <= 32'd0;
        cpu_cycle_cnt <= 32'd0;
        delay_counter <= 32'd0;
    end else begin
        case (r_state)
            R_IDLE: begin
                in_rvalid <= 1'b0;
                if (in_arvalid && in_arready) begin
                    // 接收 AR 请求
                    saved_arid    <= in_arid;
                    saved_araddr  <= in_araddr;
                    saved_arlen   <= in_arlen;
                    saved_arsize  <= in_arsize;
                    saved_arburst <= in_arburst;
                    
                    in_arready <= 1'b0;
                    out_arvalid <= 1'b1;
                    
                    beat_recv_cnt <= 4'd0;
                    beat_send_cnt <= 4'd0;
                    dev_cycle_cnt <= 32'd1;  // 从 AR 有效开始计时
                    cpu_cycle_cnt <= 32'd1;
                    
                    r_state <= R_WAIT_DEV;
                end
            end
            
            R_WAIT_DEV: begin
                // AR 通道握手
                if (out_arvalid && out_arready) begin
                    out_arvalid <= 1'b0;
                    out_rready <= 1'b1;
                end
                
                // 设备周期计数
                dev_cycle_cnt <= dev_cycle_cnt + 1;
                cpu_cycle_cnt <= cpu_cycle_cnt + 1;
                
                // 接收设备返回的数据
                if (out_rvalid && out_rready) begin
                    beat_data[beat_recv_cnt] <= out_rdata;
                    beat_resp[beat_recv_cnt] <= out_rresp;
                    beat_last[beat_recv_cnt] <= out_rlast;
                    beat_target[beat_recv_cnt] <= calc_delay(dev_cycle_cnt);
                    beat_recv_cnt <= beat_recv_cnt + 1;
                    
                    if (out_rlast) begin
                        out_rready <= 1'b0;
                        // 开始向 CPU 返回数据
                        r_state <= R_DELAY;
                    end
                end
            end
            
            R_DELAY: begin
                cpu_cycle_cnt <= cpu_cycle_cnt + 1;
                
                // 检查是否到达目标时间
                if (cpu_cycle_cnt >= beat_target[beat_send_cnt]) begin
                    if (in_rready || !in_rvalid) begin
                        in_rvalid <= 1'b1;
                        
                        if (in_rready && in_rvalid) begin
                            // 完成一次握手
                            beat_send_cnt <= beat_send_cnt + 1;
                            
                            if (beat_last[beat_send_cnt]) begin
                                // 事务完成
                                in_rvalid <= 1'b0;
                                in_arready <= 1'b1;
                                r_state <= R_IDLE;
                            end
                        end
                    end
                end
            end
        endcase
    end
end

// ================================================================
// 写通道延迟处理（简化版，仅单次写）
// ================================================================
// ... 类似逻辑 ...

endmodule
```

### 步骤 D3：验证延迟校准

在波形中验证等式：`(t_i - t_0) * r = t_i' - t_0`

```bash
cd npc
make ARCH=riscv32e-ysyxsoc sim
# 观察波形，验证延迟校准
```

---

## 验收标准

### Part A：扩展 Cache Line
- [ ] cache line 大小可配置（4/8/16/32B）
- [ ] 地址分解正确
- [ ] 命中判断正确
- [ ] refill 逻辑正确填充所有字
- [ ] LRU 更新正确

### Part B：AXI4 突发传输
- [ ] IFU_AXI4 正确发送突发请求
- [ ] 正确接收多拍数据
- [ ] `rlast` 信号处理正确
- [ ] 仲裁器正确转发突发信号

### Part C：AXI SDRAM
- [ ] 成功切换到 AXI 接口
- [ ] 基本程序运行正确

### Part D：AXI4 延迟模块
- [ ] 读事务延迟校准正确
- [ ] 突发传输每个 beat 延迟正确
- [ ] 波形验证等式成立

### 性能验证
- [ ] 运行 microbench，比较突发传输前后的性能
- [ ] 记录不同 cache line 大小的性能数据

## 相关文件

| 文件 | 说明 |
|------|------|
| `npc/vsrc/core/ICache.v` | 参数化 ICache |
| `npc/vsrc/core/IFU_AXI4.v` | 新增，AXI4 Master |
| `npc/vsrc/core/AXI4_Arbiter.v` | 修改，支持完整 AXI4 |
| `ysyxSoC/src/Top.scala` | 修改 sdramUseAXI |
| `ysyxSoC/perip/amba/axi4_delayer.v` | 完整实现 |

## 预计工作量

- Part A（ICache 扩展）：4-6 小时
- Part B（AXI4 突发传输）：3-4 小时
- Part C（AXI SDRAM 切换）：1-2 小时
- Part D（AXI4 延迟模块）：4-6 小时
- 测试和验证：4-6 小时
