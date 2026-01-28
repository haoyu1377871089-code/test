# NPC 处理器取指时序图 (16B Cache Line + AXI4 Burst)

本文档详细描述了启用 I-Cache 和 AXI4 Burst 后，NPC 处理器执行一条指令时的完整时序流程。

## 图示

### 系统架构图
![NPC Architecture](npc_architecture_diagram.png)

### I-Cache Miss 时序图
![I-Cache Burst Timing](icache_burst_timing_diagram.png)

## 系统架构概览

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           ysyx_00000000 (NPC Top)                            │
│                                                                               │
│  ┌─────────┐    ┌─────────┐    ┌──────────┐    ┌──────────────┐              │
│  │  EXU    │◄───│ ICache  │◄───│ IFU_AXI4 │◄───│ AXI4_Arbiter │◄─────────┐   │
│  │         │    │ (4KB,   │    │ (Burst   │    │              │          │   │
│  │         │    │ 2-way,  │    │ Master)  │    │              │          │   │
│  │         │    │ 16B/ln) │    │          │    │              │          │   │
│  └────┬────┘    └─────────┘    └──────────┘    │              │          │   │
│       │                                        │              │          │   │
│       │         ┌──────────┐                   │              │          │   │
│       └────────►│ LSU_AXI4 │──────────────────►│              │          │   │
│                 │ (Single  │                   └──────────────┘          │   │
│                 │  Beat)   │                          │                  │   │
│                 └──────────┘                          │                  │   │
└───────────────────────────────────────────────────────┼──────────────────┘   │
                                                        │                      │
                                                        ▼                      │
┌──────────────────────────────────────────────────────────────────────────────┤
│                              ysyxSoC                                         │
│                                                                               │
│   ┌─────────────────┐    ┌───────────────┐    ┌────────────────┐             │
│   │  AXI4 Crossbar  │───►│ AXI4 Delayer  │───►│ SDRAM (AXI4)   │             │
│   │                 │    │               │    │                │             │
│   │                 │───►│ APB Bridge    │───►│ Flash/UART/... │             │
│   └─────────────────┘    └───────────────┘    └────────────────┘             │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 时序图 1: I-Cache Hit (指令命中)

当请求的指令已在 Cache 中时，只需 2 个周期即可完成取指。

```
Cycle        │  1  │  2  │  3  │
─────────────┼─────┼─────┼─────┼────
             │     │     │     │
EXU State    │IDLE │IDLE │EXEC │    EXU 在 T2 收到指令，T3 开始执行
             │     │     │     │
PC           │ PC  │ PC  │ PC  │    PC 保持不变
             │     │     │     │
ifu_req      │__╱▔▔│▔╲__│     │    T1: CPU 发出取指请求
             │     │     │     │
ICache State │IDLE │LKUP │IDLE │    T2: 在 LOOKUP 状态检查 tag
             │     │     │     │
cache_hit    │     │__╱▔▔│▔╲__│    T2: Tag 比较命中
             │     │     │     │
cpu_rvalid   │     │__╱▔▔│▔╲__│    T2: 返回数据有效
             │     │     │     │
cpu_rdata    │     │INST │INST │    T2: 输出命中的指令
             │     │     │     │
op_en_ifu    │     │__╱▔▔│▔╲__│    T2: 指令使能送往 EXU
             │     │     │     │
LRU Update   │     │ ✓  │     │    T2: 更新 LRU 位
             │     │     │     │
```

**关键路径分析 (Cache Hit):**
- T1: CPU 发起 `ifu_req`，ICache 从 `S_IDLE` → `S_LOOKUP`
- T2: ICache 进行 tag 比较，命中时直接返回数据，更新 LRU
- T3: EXU 开始执行指令

**总延迟: 2 cycles (AMAT ≈ 2 cycles for hit)**

---

## 时序图 2: I-Cache Miss + AXI4 Burst Refill (指令未命中)

当请求的指令不在 Cache 中时，需要通过 AXI4 Burst 从 PSRAM/Flash 读取整个 Cache Line (16 bytes = 4 words)。

```
Cycle    │  1  │  2  │  3  │  4  │ ... │  N  │N+1  │N+2  │N+3  │N+4  │N+5  │
─────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼────
         │     │     │     │     │     │     │     │     │     │     │     │
EXU St   │IDLE │IDLE │IDLE │IDLE │IDLE │IDLE │IDLE │IDLE │IDLE │IDLE │EXEC │
         │     │     │     │     │     │     │     │     │     │     │     │
ifu_req  │__╱▔▔│▔╲__│     │     │     │     │     │     │     │     │     │  T1: CPU请求
         │     │     │     │     │     │     │     │     │     │     │     │
ICache   │IDLE │LKUP │ REQ │DATA │DATA │DATA │DATA │DATA │DATA │DATA │IDLE │
State    │     │     │     │     │     │     │     │     │     │     │     │
         │     │     │     │     │     │     │     │     │     │     │     │
cache_hit│     │__╱▔▔│▔╲__│     │     │     │     │     │     │     │     │  T2: Miss!
         │     │ =0 │     │     │     │     │     │     │     │     │     │
         │     │     │     │     │     │     │     │     │     │     │     │
mem_req  │     │     │__╱▔▔│▔╲__│     │     │     │     │     │     │     │  T3: 发送AXI请求
         │     │     │     │     │     │     │     │     │     │     │     │
mem_addr │     │     │ALIN │     │     │     │     │     │     │     │     │  Line-aligned
         │     │     │     │     │     │     │     │     │     │     │     │
mem_len  │     │     │ =3  │     │     │     │     │     │     │     │     │  4-beat burst
         │     │     │     │     │     │     │     │     │     │     │     │

[IFU_AXI4 State Machine]
IFU St   │IDLE │IDLE │ AR  │ AR  │ ... │  R  │  R  │  R  │  R  │  R  │IDLE │
         │     │     │     │     │     │     │     │     │     │     │     │
arvalid  │     │     │__╱▔▔│▔▔▔▔│▔╲__│     │     │     │     │     │     │  AR handshake
arready  │     │     │     │__╱▔▔│▔╲__│     │     │     │     │     │     │  (等待仲裁)
araddr   │     │     │ALIN │ALIN │     │     │     │     │     │     │     │
arlen    │     │     │ =3  │ =3  │     │     │     │     │     │     │     │
         │     │     │     │     │     │     │     │     │     │     │     │

[AXI4 Read Data Channel - 4 Beat Burst]
rvalid   │     │     │     │     │     │__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__│     │  4 beats
rdata    │     │     │     │     │     │ W0  │ W1  │ W2  │ W3  │     │     │  Word 0-3
rlast    │     │     │     │     │     │     │     │     │__╱▔▔│▔╲__│     │  Last beat
rready   │     │     │     │     │__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__│     │
         │     │     │     │     │     │     │     │     │     │     │     │

[ICache Refill - Write to Cache]
refill_  │     │     │     │     │     │  0  │  1  │  2  │  3  │     │     │  Word count
word_cnt │     │     │     │     │     │     │     │     │     │     │     │
         │     │     │     │     │     │     │     │     │     │     │     │
data[]   │     │     │     │     │     │ ✓W0 │ ✓W1 │ ✓W2 │ ✓W3 │     │     │  写入Cache
         │     │     │     │     │     │     │     │     │     │     │     │
valid[]  │     │     │     │     │     │     │     │     │  ✓  │     │     │  Refill完成
tags[]   │     │     │     │     │     │     │     │     │  ✓  │     │     │  时设置
         │     │     │     │     │     │     │     │     │     │     │     │
cpu_rval │     │     │     │     │     │     │     │     │__╱▔▔│▔╲__│     │  返回数据
cpu_rdata│     │     │     │     │     │     │     │     │ REQ │     │     │  请求的word
         │     │     │     │     │     │     │     │     │WORD │     │     │
```

**详细阶段说明:**

### Phase 1: Cache Lookup (T1-T2)
- T1: CPU 发出 `ifu_req`，ICache 捕获地址，进入 `S_LOOKUP`
- T2: Tag 比较，发现 Miss，记录 LRU way，进入 `S_REFILL_REQ`

### Phase 2: AXI4 AR Channel (T3-TN)
- T3: ICache 发送 `mem_req`，地址对齐到 Cache Line 边界
  - `mem_addr = {addr[31:4], 4'b0000}` (16B 对齐)
  - `mem_len = 3` (4-beat burst: len+1 = 4)
- IFU_AXI4 设置 AR channel:
  - `araddr` = line-aligned address
  - `arlen = 3` (4 beats)
  - `arsize = 2` (4 bytes per beat)
  - `arburst = 1` (INCR)
  - `arvalid = 1`
- 等待 `arready` (可能需要仲裁)

### Phase 3: AXI4 R Channel - Burst Data (TN+1 to TN+4)
- 收到 4 个连续的数据 beat:
  - Beat 0: Word 0 (`rvalid`, `rdata=W0`)
  - Beat 1: Word 1 (`rvalid`, `rdata=W1`)
  - Beat 2: Word 2 (`rvalid`, `rdata=W2`)
  - Beat 3: Word 3 (`rvalid`, `rdata=W3`, `rlast=1`)
- 每个 beat 写入 `data[way][set][word_cnt]`

### Phase 4: Refill Complete (TN+4)
- `rlast` 时完成 refill:
  - 设置 `valid[way][set] = 1`
  - 设置 `tags[way][set] = req_tag`
  - 更新 `lru[set]`
  - 返回 `cpu_rvalid = 1`, `cpu_rdata = data[way][set][req_word]`

**总延迟: ~2975 cycles (实测平均)**
- AR 握手: ~10 cycles (仲裁 + 传播)
- SDRAM 访问: ~2900 cycles (AXI4 Delayer + SDRAM 延迟)
- 4-beat burst: 4 cycles
- 数据返回: ~50 cycles

---

## 时序图 3: Load 指令执行 (LW)

Load 指令通过 LSU_AXI4 访问数据存储器（单拍事务）。

```
Cycle    │  1  │  2  │  3  │  4  │  5  │ ... │  N  │N+1  │N+2  │N+3  │
─────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼────
         │     │     │     │     │     │     │     │     │     │     │
EXU St   │EXEC │EXEC │EXEC │W_LSU│W_LSU│W_LSU│W_LSU│W_LSU│ WB  │IDLE │
         │(DEC)│(EXE)│(MEM)│     │     │     │     │     │     │     │
         │     │     │     │     │     │     │     │     │     │     │
op_en    │__╱▔▔│▔╲__│     │     │     │     │     │     │     │     │  T1: 收到LW指令
         │     │     │     │     │     │     │     │     │     │     │
lsu_req  │     │     │__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__│     │  T3: EXU请求LSU
lsu_wen  │     │     │  0  │  0  │  0  │  0  │  0  │  0  │     │     │  读操作
lsu_addr │     │     │ADDR │ADDR │ADDR │ADDR │ADDR │ADDR │     │     │
         │     │     │     │     │     │     │     │     │     │     │

[LSU_AXI4 State Machine]
LSU St   │IDLE │IDLE │ AR  │ AR  │ AR  │ ... │  R  │  R  │IDLE │IDLE │
         │     │     │     │     │     │     │     │     │     │     │
arvalid  │     │     │__╱▔▔│▔▔▔▔│▔╲__│     │     │     │     │     │
arready  │     │     │     │     │__╱▔▔│▔╲__│     │     │     │     │  仲裁延迟
araddr   │     │     │ADDR │ADDR │     │     │     │     │     │     │
arlen    │     │     │  0  │  0  │     │     │     │     │     │     │  单拍
         │     │     │     │     │     │     │     │     │     │     │
rvalid   │     │     │     │     │     │     │__╱▔▔│▔╲__│     │     │
rdata    │     │     │     │     │     │     │DATA │DATA │     │     │
rlast    │     │     │     │     │     │     │__╱▔▔│▔╲__│     │     │  单拍必有rlast
         │     │     │     │     │     │     │     │     │     │     │
lsu_rval │     │     │     │     │     │     │     │__╱▔▔│▔╲__│     │
lsu_rdata│     │     │     │     │     │     │     │DATA │     │     │
         │     │     │     │     │     │     │     │     │     │     │
rd_wdata │     │     │     │     │     │     │     │DATA │     │     │  写回寄存器
```

**总延迟: ~181 cycles (实测平均, SRAM 访问)**

---

## 时序图 4: Store 指令执行 (SW)

Store 指令通过 LSU_AXI4 写入数据存储器。

```
Cycle    │  1  │  2  │  3  │  4  │  5  │ ... │  N  │N+1  │N+2  │
─────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼────
         │     │     │     │     │     │     │     │     │     │
EXU St   │EXEC │EXEC │EXEC │W_LSU│W_LSU│W_LSU│W_LSU│ WB  │IDLE │
         │(DEC)│(EXE)│(MEM)│     │     │     │     │     │     │
         │     │     │     │     │     │     │     │     │     │
lsu_req  │     │     │__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__│     │
lsu_wen  │     │     │  1  │  1  │  1  │  1  │  1  │     │     │  写操作
lsu_addr │     │     │ADDR │ADDR │ADDR │ADDR │ADDR │     │     │
lsu_wdata│     │     │DATA │DATA │DATA │DATA │DATA │     │     │
lsu_wmask│     │     │MASK │MASK │MASK │MASK │MASK │     │     │
         │     │     │     │     │     │     │     │     │     │

[LSU_AXI4 - Write Transaction]
LSU St   │IDLE │IDLE │ AW  │ AW  │  W  │ ... │  B  │  B  │IDLE │
         │     │     │     │     │     │     │     │     │     │
awvalid  │     │     │__╱▔▔│▔╲__│     │     │     │     │     │
awready  │     │     │     │__╱▔▔│▔╲__│     │     │     │     │
awaddr   │     │     │ADDR │ADDR │     │     │     │     │     │
awlen    │     │     │  0  │  0  │     │     │     │     │     │  单拍
         │     │     │     │     │     │     │     │     │     │
wvalid   │     │     │     │     │__╱▔▔│▔╲__│     │     │     │
wdata    │     │     │     │     │DATA │DATA │     │     │     │
wstrb    │     │     │     │     │MASK │MASK │     │     │     │
wlast    │     │     │     │     │__╱▔▔│▔╲__│     │     │     │  单拍
wready   │     │     │     │     │     │__╱▔▔│▔╲__│     │     │
         │     │     │     │     │     │     │     │     │     │
bvalid   │     │     │     │     │     │     │__╱▔▔│▔╲__│     │
bresp    │     │     │     │     │     │     │ OK  │ OK  │     │
bready   │     │     │     │     │     │__╱▔▔│▔▔▔▔│▔╲__│     │
         │     │     │     │     │     │     │     │     │     │
lsu_rval │     │     │     │     │     │     │     │__╱▔▔│▔╲__│  完成信号
```

**总延迟: ~117 cycles (实测平均, SRAM 访问)**

---

## 时序图 5: IFU/LSU 仲裁 (同时请求)

当 ICache Miss 和 LSU 请求同时发生时，AXI4_Arbiter 进行仲裁。

```
Cycle    │  1  │  2  │  3  │  4  │  5  │  6  │  7  │ ... │
─────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼────
         │     │     │     │     │     │     │     │     │
[同时到达的请求]
ifu_arval│__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__│     │     │  IFU请求 (burst)
lsu_arval│__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__│  LSU请求 (等待)
         │     │     │     │     │     │     │     │     │

[AXI4_Arbiter - IFU优先]
arb_grant│ IFU │ IFU │ IFU │ IFU │ IFU │ IFU │ LSU │ LSU │
arb_state│IDLE │ IFU │ IFU │ IFU │ IFU │ IFU │ LSU │ LSU │
         │     │BUSY │BUSY │BUSY │BUSY │BUSY │BUSY │BUSY │
         │     │     │     │     │     │     │     │     │
[输出到Slave]
s_arvalid│__╱▔▔│▔▔▔▔│▔╲__│     │__╱▔▔│▔▔▔▔│▔▔▔▔│▔╲__│
s_araddr │ IFU │ IFU │     │     │ IFU │ IFU │ LSU │ LSU │  先IFU后LSU
s_arlen  │  3  │  3  │     │     │  3  │  3  │  0  │  0  │  IFU:burst LSU:single
         │     │     │     │     │     │     │     │     │

[Slave Response]
         │     │     │     │     │ R0  │ R1  │ R2  │ R3  │  IFU 4-beat burst
ifu_rval │     │     │     │     │__╱▔▔│▔▔▔▔│▔▔▔▔│▔▔▔▔│▔╲__  完成后释放
ifu_rlast│     │     │     │     │     │     │     │__╱▔▔│▔╲__
         │     │     │     │     │     │     │     │     │
lsu_rval │     │     │     │     │     │     │     │     │  等待IFU完成
         │     │     │     │     │     │     │     │     │  后才能开始
```

**仲裁策略:**
- IFU 优先级高于 LSU (降低取指延迟)
- 事务级仲裁：必须等当前事务完成（rlast/bvalid）才切换
- Burst 传输：IFU 可能占用总线多个周期

---

## 完整指令执行流程 (从 Fetch 到 Writeback)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        完整指令执行流程                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Phase 1: FETCH (取指)
┌─────────────────────────────────────────────────────────────────────────────┐
│  PC Register ──► ICache Lookup                                               │
│       │              │                                                       │
│       │              ├──► HIT:  Return instruction (2 cycles)               │
│       │              │                                                       │
│       │              └──► MISS: AXI4 Burst Refill                           │
│       │                         │                                           │
│       │                         ├──► IFU_AXI4: AR channel (addr, len=3)     │
│       │                         │                                           │
│       │                         ├──► AXI4_Arbiter: Grant to IFU             │
│       │                         │                                           │
│       │                         ├──► ysyxSoC: AXI4 Crossbar → Delayer      │
│       │                         │                     │                     │
│       │                         │                     └──► SDRAM/Flash      │
│       │                         │                                           │
│       │                         ├──► R channel: 4 beats (W0,W1,W2,W3)       │
│       │                         │                                           │
│       │                         └──► ICache: Write line, set valid/tag      │
│       │                                                                     │
│       └──────────────────────────► Return: cpu_rvalid, cpu_rdata            │
└─────────────────────────────────────────────────────────────────────────────┘

Phase 2: DECODE + EXECUTE (译码 + 执行)
┌─────────────────────────────────────────────────────────────────────────────┐
│  op_ifu ──► IDU: Decode instruction fields                                   │
│              │                                                               │
│              ├──► rs1, rs2, rd, imm, opcode, funct3, funct7                 │
│              │                                                               │
│              └──► EXU: Execute operation                                     │
│                    │                                                         │
│                    ├──► ALU: Arithmetic/Logic                               │
│                    ├──► Branch: Condition evaluation                        │
│                    └──► Address: Load/Store address calculation             │
└─────────────────────────────────────────────────────────────────────────────┘

Phase 3: MEMORY (访存 - 仅 Load/Store)
┌─────────────────────────────────────────────────────────────────────────────┐
│  EXU ──► LSU_AXI4                                                            │
│           │                                                                  │
│           ├──► Load:  AR → R (single beat)                                  │
│           │           │                                                      │
│           │           └──► ~181 cycles (SRAM)                               │
│           │                                                                  │
│           └──► Store: AW → W → B (single beat)                              │
│                       │                                                      │
│                       └──► ~117 cycles (SRAM)                               │
└─────────────────────────────────────────────────────────────────────────────┘

Phase 4: WRITEBACK (写回)
┌─────────────────────────────────────────────────────────────────────────────┐
│  Result ──► Register File                                                    │
│     │                                                                        │
│     ├──► ALU result → rd                                                    │
│     ├──► Load data → rd                                                     │
│     └──► PC+4 / PC+offset → rd (JAL/JALR)                                   │
│                                                                              │
│  PC Update ──► next_pc                                                       │
│     │                                                                        │
│     ├──► Sequential: PC + 4                                                 │
│     ├──► Branch taken: PC + imm                                             │
│     └──► Jump: rd1 + imm (JALR) or PC + imm (JAL)                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 性能参数汇总

| 操作 | 延迟 (cycles) | 说明 |
|------|---------------|------|
| I-Cache Hit | 2 | Tag 比较 + 数据返回 |
| I-Cache Miss (16B line) | ~2975 | AR握手 + SDRAM访问 + 4-beat burst |
| Load (SRAM) | ~181 | 单拍 AXI4 读事务 |
| Store (SRAM) | ~117 | 单拍 AXI4 写事务 |
| ALU 执行 | 1 | 组合逻辑 |
| 分支判断 | 1 | 条件评估 |

## Cache 参数

| 参数 | 值 | 说明 |
|------|-----|------|
| CACHE_SIZE | 4 KB | 总容量 |
| LINE_SIZE | 16 B | Cache Line 大小 |
| NUM_WAYS | 2 | 2路组相联 |
| NUM_SETS | 128 | 组数 |
| TAG_WIDTH | 23 bits | Tag 宽度 |
| INDEX_WIDTH | 5 bits | Index 宽度 |
| OFFSET_WIDTH | 4 bits | Offset 宽度 |
| WORDS_PER_LINE | 4 | 每行字数 |
| Hit Rate | 99.67% | microbench 实测 |
| AMAT | 11.65 cycles | 平均访存延迟 |

## AXI4 Burst 参数

| 参数 | 值 | 说明 |
|------|-----|------|
| arlen | 3 | 4-beat burst (len+1) |
| arsize | 2 | 4 bytes per beat |
| arburst | 1 | INCR (incrementing address) |
| Total transfer | 16 bytes | 4 × 4 bytes |
