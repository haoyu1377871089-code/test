# LW 指令完整执行时序图

> 本文档详细展示 `lw x6, 8(x10)` 指令在 NPC 处理器中从取指到写回的完整执行过程，包括所有模块的状态变化和信号交互。

## 一、指令概述

### 1.1 典型指令

```
lw x6, 8(x10)
```

| 属性 | 值 |
|------|-----|
| 机器码 | `0x00852303` |
| 含义 | `x6 = Memory[x10 + 8]` |
| 类型 | I 型指令（Load） |

### 1.2 指令编码分解

```
0x00852303 = 0000_0000_1000_0101_0010_0011_0000_0011

| imm[11:0]    | rs1   | funct3 | rd    | opcode  |
| 000000001000 | 01010 | 010    | 00110 | 0000011 |
|     8        |  x10  |  LW    |  x6   |  Load   |
```

### 1.3 涉及的模块

| 模块 | 文件 | 功能 |
|------|------|------|
| TopModule | `ysyx_00000000.v` | 顶层控制、PC管理 |
| ICache | `ICache.v` | 指令缓存（可选） |
| IFU_AXI | `IFU_AXI.v` | 取指AXI接口 |
| Arbiter | `AXI4_Lite_Arbiter.v` | 总线仲裁 |
| EXU | `EXU.v` | 执行单元 |
| RegisterFile | `RegisterFile.v` | 寄存器文件 |
| LSU_AXI | `LSU_AXI.v` | 访存AXI接口 |

---

## 二、完整执行时序图

### 2.1 主时序图（ICache 命中场景）

```mermaid
sequenceDiagram
    autonumber
    participant TOP as TopModule
    participant IC as ICache
    participant EXU as EXU
    participant RF as RegisterFile
    participant LSU as LSU_AXI
    participant ARB as Arbiter
    participant MEM as Memory/SoC

    Note over TOP: PC = 0x30000010

    rect rgb(200, 230, 255)
    Note over TOP,IC: 阶段1: 取指 (Fetch) - ICache命中
    TOP->>IC: cpu_req=1, cpu_addr=0x30000010
    Note over IC: state: IDLE -> LOOKUP
    IC->>IC: 检查 Tag[31:11], Index[10:2]
    Note over IC: hit_way0 或 hit_way1 = 1
    IC-->>TOP: cpu_rvalid=1, cpu_rdata=0x00852303
    Note over IC: state: LOOKUP -> IDLE
    TOP->>TOP: op_ifu=0x00852303, op_en_ifu=1
    end

    rect rgb(255, 230, 200)
    Note over EXU,RF: 阶段2: 译码 (Decode)
    TOP->>EXU: op=0x00852303, op_en=1
    Note over EXU: state: IDLE -> DECODE
    EXU->>EXU: 解析指令字段
    Note over EXU: opcode=0000011 (Load)<br/>rd=00110 (x6)<br/>funct3=010 (LW)<br/>rs1=01010 (x10)<br/>imm=0x008 (8)
    EXU->>RF: raddr1=10
    RF-->>EXU: rdata1=0x80000000 (x10的值)
    end

    rect rgb(200, 255, 200)
    Note over EXU,LSU: 阶段3: 执行 + 发起访存 (Execute)
    Note over EXU: state: DECODE -> EXECUTE
    EXU->>EXU: 计算访存地址
    Note over EXU: lsu_addr = rdata1 + imm_i_sext<br/>= 0x80000000 + 8<br/>= 0x80000008
    EXU->>LSU: lsu_req=1, lsu_wen=0, lsu_addr=0x80000008
    Note over EXU: lsu_wmask=4'b1111 (LW读4字节)
    Note over EXU: state: EXECUTE -> WAIT_LSU
    end

    rect rgb(255, 255, 200)
    Note over LSU,MEM: 阶段4: LSU访存 (Memory Access)
    LSU->>ARB: arvalid=1, araddr=0x80000008
    Note over ARB: state: IDLE -> ARB_LSU
    Note over ARB: 授权LSU使用总线
    ARB->>MEM: s_arvalid=1, s_araddr=0x80000008
    MEM-->>ARB: s_arready=1
    Note over ARB: AR通道握手完成
    Note over MEM: 读取PSRAM数据...<br/>(约180周期)
    MEM-->>ARB: s_rvalid=1, s_rdata=0xDEADBEEF
    ARB-->>LSU: m1_rvalid=1, m1_rdata=0xDEADBEEF
    Note over ARB: state: ARB_LSU -> IDLE
    LSU-->>EXU: lsu_rvalid=1, lsu_rdata=0xDEADBEEF
    end

    rect rgb(255, 200, 255)
    Note over EXU,RF: 阶段5: 写回 (Writeback)
    Note over EXU: state: WAIT_LSU -> WRITEBACK
    EXU->>EXU: wdata = lsu_rdata = 0xDEADBEEF
    EXU->>RF: wen=1, waddr=6, wdata=0xDEADBEEF
    Note over RF: x6 = 0xDEADBEEF
    EXU->>EXU: ex_end <= ~ex_end (翻转)
    Note over EXU: state: WRITEBACK -> IDLE
    end

    rect rgb(230, 230, 230)
    Note over TOP: 阶段6: PC更新
    EXU-->>TOP: ex_end变化, next_pc=0x30000014
    TOP->>TOP: 检测ex_end != ex_end_prev
    TOP->>TOP: update_pc=1
    TOP->>TOP: pc = next_pc = 0x30000014
    Note over TOP: 准备取下一条指令
    end
```

### 2.2 ICache 未命中场景时序图

```mermaid
sequenceDiagram
    autonumber
    participant TOP as TopModule
    participant IC as ICache
    participant IFU as IFU_AXI
    participant ARB as Arbiter
    participant MEM as Memory/SoC

    Note over TOP: PC = 0x30000010 (首次访问)

    rect rgb(200, 230, 255)
    Note over TOP,MEM: 阶段1: 取指 (Fetch) - ICache未命中
    TOP->>IC: cpu_req=1, cpu_addr=0x30000010
    Note over IC: state: IDLE -> LOOKUP
    IC->>IC: 检查缓存
    Note over IC: cache_hit = 0 (miss!)
    Note over IC: state: LOOKUP -> REFILL
    IC->>IFU: mem_req=1, mem_addr=0x30000010
    IFU->>ARB: arvalid=1, araddr=0x30000010
    Note over ARB: state: IDLE -> ARB_IFU
    ARB->>MEM: s_arvalid=1, s_araddr=0x30000010
    MEM-->>ARB: s_arready=1
    Note over MEM: 从Flash XIP读取...<br/>(约750周期)
    MEM-->>ARB: s_rvalid=1, s_rdata=0x00852303
    ARB-->>IFU: m0_rvalid=1, m0_rdata=0x00852303
    Note over ARB: state: ARB_IFU -> IDLE
    IFU-->>IC: mem_rvalid=1, mem_rdata=0x00852303
    Note over IC: 更新Cache: valid=1, tag, data
    Note over IC: 更新LRU位
    Note over IC: state: REFILL -> IDLE
    IC-->>TOP: cpu_rvalid=1, cpu_rdata=0x00852303
    TOP->>TOP: op_ifu=0x00852303, op_en_ifu=1
    end
```

---

## 三、各模块状态机转换详图

### 3.1 EXU 状态机（LW指令执行路径）

```mermaid
stateDiagram-v2
    direction LR
    
    [*] --> IDLE: reset
    IDLE --> DECODE: op_en=1
    DECODE --> EXECUTE: 译码完成
    
    state EXECUTE {
        direction TB
        [*] --> CalcAddr
        CalcAddr --> SetLSU: lsu_addr=rdata1+imm
        SetLSU --> SendReq: lsu_req=1, lsu_wen=0
    }
    
    EXECUTE --> WAIT_LSU: Load/Store指令
    
    state WAIT_LSU {
        direction TB
        [*] --> WaitData
        WaitData --> DataReady: lsu_rvalid=1
        DataReady --> ProcessData: wdata=lsu_rdata
    }
    
    WAIT_LSU --> WRITEBACK: lsu_rvalid=1
    
    state WRITEBACK {
        direction TB
        [*] --> WriteReg
        WriteReg --> FlipExEnd: wen=1, waddr=rd
        FlipExEnd --> Done: ex_end翻转
    }
    
    WRITEBACK --> IDLE: 写回完成
```

### 3.2 ICache 状态机

```mermaid
stateDiagram-v2
    [*] --> S_IDLE: reset
    
    S_IDLE --> S_LOOKUP: cpu_req=1
    Note right of S_IDLE: 锁存cpu_addr
    
    S_LOOKUP --> S_IDLE: cache_hit=1
    Note right of S_LOOKUP: 返回数据,更新LRU
    
    S_LOOKUP --> S_REFILL: cache_hit=0
    Note right of S_LOOKUP: 记录refill_index,tag,way
    
    S_REFILL --> S_IDLE: mem_rvalid=1
    Note right of S_REFILL: 写入cache,返回数据
```

### 3.3 IFU_AXI 状态机

```mermaid
stateDiagram-v2
    [*] --> IFU_IDLE: reset
    
    IFU_IDLE --> IFU_WAIT_AR: req=1
    Note right of IFU_IDLE: arvalid=1, araddr=addr
    
    IFU_WAIT_AR --> IFU_WAIT_R: arready=1
    Note right of IFU_WAIT_AR: AR通道握手完成
    
    IFU_WAIT_R --> IFU_IDLE: rvalid=1
    Note right of IFU_WAIT_R: 锁存rdata, rvalid_out=1
```

### 3.4 LSU_AXI 读操作流程

```mermaid
stateDiagram-v2
    [*] --> LSU_IDLE: reset
    
    state LSU_IDLE {
        [*] --> CheckReq
        CheckReq --> IsRead: req=1, wen=0
    }
    
    LSU_IDLE --> LSU_AR: 读请求
    Note right of LSU_IDLE: arvalid=1, araddr=addr, rready=1
    
    LSU_AR --> LSU_WAIT_R: arready=1
    Note right of LSU_AR: AR握手完成
    
    LSU_WAIT_R --> LSU_IDLE: rvalid=1
    Note right of LSU_WAIT_R: 数据对齐, rvalid_out=1
```

### 3.5 Arbiter 状态机

```mermaid
stateDiagram-v2
    [*] --> ARB_IDLE: reset
    
    ARB_IDLE --> ARB_IFU: ifu_req=1
    Note right of ARB_IDLE: IFU优先级高
    
    ARB_IDLE --> ARB_LSU: lsu_req=1 且 ifu_req=0
    
    ARB_IFU --> ARB_IDLE: rvalid且rready 或 bvalid且bready
    Note right of ARB_IFU: IFU事务完成
    
    ARB_LSU --> ARB_IDLE: rvalid且rready 或 bvalid且bready
    Note right of ARB_LSU: LSU事务完成
```

---

## 四、逐周期信号变化表

假设：
- ICache 命中（取指 2 周期）
- PSRAM 读延迟约 180 周期
- x10 = 0x80000000

### 4.1 取指阶段（T0-T2）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T0 | TOP | pc | 0x30000010 | 当前PC |
| T0 | TOP | ifu_req | 0→1 | 发起取指请求 |
| T0 | TOP | ifu_addr | 0x30000010 | 取指地址 |
| T0 | ICache | state | IDLE→LOOKUP | 状态转换 |
| T0 | ICache | req_addr_reg | 0x30000010 | 锁存地址 |
| T1 | ICache | req_tag | 0x060000 | Tag[31:11] |
| T1 | ICache | req_index | 0x004 | Index[10:2] |
| T1 | ICache | hit_way0/1 | 1/0 | 命中way0 |
| T1 | ICache | cache_hit | 1 | 缓存命中 |
| T1 | ICache | cpu_rvalid | 0→1 | 数据有效 |
| T1 | ICache | cpu_rdata | 0x00852303 | 指令数据 |
| T1 | ICache | lru[idx] | 0→1 | 更新LRU |
| T1 | ICache | state | LOOKUP→IDLE | 返回空闲 |
| T2 | TOP | op_ifu | 0x00852303 | 锁存指令 |
| T2 | TOP | op_en_ifu | 0→1 | 指令有效 |

### 4.2 译码阶段（T3）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T3 | EXU | state | IDLE→DECODE | 进入译码 |
| T3 | EXU | opcode | 7'b0000011 | Load类型 |
| T3 | EXU | funct3 | 3'b010 | LW指令 |
| T3 | EXU | rd | 5'b00110 | 目标: x6 |
| T3 | EXU | rs1 | 5'b01010 | 源: x10 |
| T3 | EXU | imm_i | 12'h008 | 立即数: 8 |
| T3 | EXU | imm_i_sext | 32'h00000008 | 符号扩展 |
| T3 | RF | raddr1 | 10 | 读地址 |
| T3 | RF | rdata1 | 0x80000000 | x10的值 |

### 4.3 执行阶段（T4）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T4 | EXU | state | DECODE→EXECUTE | 进入执行 |
| T4 | EXU | lsu_addr | 0x80000008 | =rdata1+imm |
| T4 | EXU | lsu_req | 0→1 | LSU请求 |
| T4 | EXU | lsu_wen | 0 | 读操作 |
| T4 | EXU | lsu_wmask | 4'b1111 | 读4字节 |
| T4 | EXU | waddr | 6 | 准备写x6 |
| T4 | EXU | wen | 1 | 准备写回 |
| T4 | EXU | next_pc | 0x30000014 | PC+4 |
| T4 | EXU | state | EXECUTE→WAIT_LSU | 等待LSU |

### 4.4 访存阶段（T5-T185，约180周期）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T5 | LSU | arvalid | 0→1 | 发起读地址 |
| T5 | LSU | araddr | 0x80000008 | 读地址 |
| T5 | LSU | rready | 0→1 | 准备接收 |
| T5 | ARB | state | IDLE→ARB_LSU | 授权LSU |
| T5 | ARB | s_arvalid | 0→1 | 转发到SoC |
| T5 | ARB | s_araddr | 0x80000008 | 转发地址 |
| T6 | MEM | s_arready | 1 | 地址握手 |
| T6 | LSU | arvalid | 1→0 | 清除请求 |
| T7-T184 | MEM | - | - | PSRAM读延迟 |
| T185 | MEM | s_rvalid | 0→1 | 数据有效 |
| T185 | MEM | s_rdata | 0xDEADBEEF | 读取数据 |
| T185 | ARB | m1_rvalid | 0→1 | 转发给LSU |
| T185 | ARB | m1_rdata | 0xDEADBEEF | 转发数据 |
| T185 | LSU | rready | 1→0 | 接收完成 |
| T185 | LSU | rvalid_out | 0→1 | 输出有效 |
| T185 | LSU | rdata_out | 0xDEADBEEF | 输出数据 |
| T185 | ARB | state | ARB_LSU→IDLE | 释放总线 |

### 4.5 写回阶段（T186）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T186 | EXU | lsu_rvalid | 1 | 收到LSU数据 |
| T186 | EXU | lsu_rdata | 0xDEADBEEF | LSU数据 |
| T186 | EXU | state | WAIT_LSU→WRITEBACK | 进入写回 |
| T186 | EXU | wdata | 0xDEADBEEF | 准备写数据 |

### 4.6 写回完成（T187）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T187 | EXU | state | WRITEBACK→IDLE | 返回空闲 |
| T187 | RF | wen | 1 | 写使能 |
| T187 | RF | waddr | 6 | 写地址 |
| T187 | RF | wdata | 0xDEADBEEF | 写数据 |
| T187 | RF | rf[6] | 0xDEADBEEF | x6更新 |
| T187 | EXU | ex_end | ~ex_end | 翻转 |
| T187 | EXU | lsu_req | 1→0 | 清除请求 |

### 4.7 PC更新（T188）

| 周期 | 模块 | 信号 | 值 | 说明 |
|------|------|------|-----|------|
| T188 | TOP | ex_end变化 | 检测到 | 执行完成 |
| T188 | TOP | update_pc | 0→1 | 准备更新PC |
| T188 | TOP | pc | 0x30000014 | 新PC值 |
| T188 | TOP | ifu_req | 0→1 | 发起新取指 |

---

## 五、AXI4-Lite 协议时序详解

### 5.1 LSU 读事务时序

```mermaid
sequenceDiagram
    participant LSU as LSU_AXI
    participant ARB as Arbiter
    participant SoC as ysyxSoC
    
    Note over LSU,SoC: AXI4-Lite 读事务
    
    rect rgb(255, 240, 200)
    Note over LSU,SoC: AR通道 (读地址)
    LSU->>ARB: arvalid=1
    LSU->>ARB: araddr=0x80000008
    ARB->>SoC: s_arvalid=1, s_araddr=0x80000008
    SoC-->>ARB: s_arready=1
    Note over ARB: 地址握手: arvalid && arready
    ARB-->>LSU: m1_arready=1
    LSU->>ARB: arvalid=0
    end
    
    rect rgb(200, 255, 200)
    Note over LSU,SoC: R通道 (读数据)
    LSU->>ARB: rready=1
    Note over SoC: 读取PSRAM...<br/>(~180周期)
    SoC-->>ARB: s_rvalid=1
    SoC-->>ARB: s_rdata=0xDEADBEEF
    SoC-->>ARB: s_rresp=2'b00 (OKAY)
    ARB-->>LSU: m1_rvalid=1, m1_rdata
    Note over LSU: 数据握手: rvalid && rready
    LSU->>ARB: rready=0
    SoC-->>ARB: s_rvalid=0
    end
```

### 5.2 AXI4-Lite 信号定义

| 通道 | 信号 | 方向 | 说明 |
|------|------|------|------|
| AR | arvalid | M→S | 读地址有效 |
| AR | arready | S→M | 读地址就绪 |
| AR | araddr | M→S | 读地址 |
| R | rvalid | S→M | 读数据有效 |
| R | rready | M→S | 读数据就绪 |
| R | rdata | S→M | 读数据 |
| R | rresp | S→M | 读响应 |

---

## 六、关键代码片段

### 6.1 EXU 处理 Load 指令（EXECUTE状态）

```verilog
// EXU.v: EXECUTE状态处理Load指令
7'b0000011: begin  // Load opcode
    lsu_addr <= rdata1 + imm_i_sext;  // 基址 + 偏移
    lsu_req <= 1;                      // 发起LSU请求
    lsu_wen <= 0;                      // 读操作
    waddr <= rd[4:0];                  // 目标寄存器
    wen <= 1;                          // 准备写回
    next_pc <= pc + 4;                 // 默认PC+4
    
    case (funct3)
        3'b000: lsu_wmask <= 4'b0001;  // LB: 1字节
        3'b001: lsu_wmask <= 4'b0011;  // LH: 2字节
        3'b010: lsu_wmask <= 4'b1111;  // LW: 4字节
        3'b100: lsu_wmask <= 4'b0001;  // LBU
        3'b101: lsu_wmask <= 4'b0011;  // LHU
    endcase
    
    state <= WAIT_LSU;  // 转到等待LSU状态
end
```

### 6.2 EXU WAIT_LSU 状态

```verilog
// EXU.v: WAIT_LSU状态
WAIT_LSU: begin
    lsu_req <= 0;  // 清除请求
    
    if (lsu_rvalid) begin
        if (opcode == 7'b0000011) begin  // Load指令
            case (funct3)
                3'b000: wdata <= {{24{lsu_rdata[7]}}, lsu_rdata[7:0]};   // LB
                3'b001: wdata <= {{16{lsu_rdata[15]}}, lsu_rdata[15:0]}; // LH
                3'b010: wdata <= lsu_rdata;                               // LW
                3'b100: wdata <= {24'b0, lsu_rdata[7:0]};                // LBU
                3'b101: wdata <= {16'b0, lsu_rdata[15:0]};               // LHU
            endcase
        end
        state <= WRITEBACK;
    end
end
```

### 6.3 LSU_AXI 读请求

```verilog
// LSU_AXI.v: 发起读请求
if (!awvalid && !wvalid && !bready && !arvalid && !rready && !rvalid_out) begin
    if (req && !in_dmem) begin
        if (!wen) begin  // 读操作
            araddr <= addr;
            arvalid <= 1'b1;
            rready <= 1'b1;
        end
    end
end
```

### 6.4 寄存器文件写入

```verilog
// RegisterFile.v: 写操作
always @(posedge clk) begin
    if (wen && waddr != 0) begin  // x0不可写
        rf[waddr] <= wdata;
    end
end
```

---

## 七、性能分析

### 7.1 周期统计

| 阶段 | 周期数 | 占比 |
|------|--------|------|
| 取指（ICache命中） | 2 | 1.1% |
| 译码 | 1 | 0.5% |
| 执行 | 1 | 0.5% |
| 访存（PSRAM） | ~180 | 96.8% |
| 写回 | 1 | 0.5% |
| PC更新 | 1 | 0.5% |
| **总计** | **~186** | 100% |

### 7.2 性能瓶颈

LW 指令的主要延迟来自 **访存阶段**，占总执行时间的 96.8%：

1. **PSRAM 延迟**：约 180 周期（通过 APB 总线访问）
2. **AXI 协议开销**：地址握手 1-2 周期

### 7.3 优化方向

| 优化方案 | 预期效果 |
|----------|----------|
| 添加 D-Cache | 减少重复访存延迟 |
| 使用 SRAM 而非 PSRAM | 将延迟从 180 降至 1-2 周期 |
| 流水线化 | 允许多指令并行 |

---

## 八、总结

LW 指令的执行经过以下完整路径：

```
PC → ICache → IFU_AXI → Arbiter → Memory
                ↓
            TopModule
                ↓
        EXU (DECODE → EXECUTE → WAIT_LSU → WRITEBACK)
                ↓
    RegisterFile ← LSU_AXI ← Arbiter ← Memory
                ↓
            PC更新
```

这条指令涉及了 NPC 处理器中几乎所有的核心模块，是理解处理器数据通路的最佳示例。
