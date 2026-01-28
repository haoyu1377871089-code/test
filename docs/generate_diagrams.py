#!/usr/bin/env python3
"""
将 Mermaid 时序图导出为 PNG 文件
使用 Mermaid.ink 在线服务
"""

import base64
import urllib.request
import urllib.parse
import os

# 输出目录
OUTPUT_DIR = "/home/hy258/ysyx-workbench/docs/diagrams"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 时序图定义
DIAGRAMS = {
    "01_lw_main_timing": """
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
    IC->>IC: 检查 Tag, Index
    Note over IC: cache_hit = 1
    IC-->>TOP: cpu_rvalid=1, cpu_rdata=0x00852303
    Note over IC: state: LOOKUP -> IDLE
    TOP->>TOP: op_ifu=0x00852303, op_en_ifu=1
    end

    rect rgb(255, 230, 200)
    Note over EXU,RF: 阶段2: 译码 (Decode)
    TOP->>EXU: op=0x00852303, op_en=1
    Note over EXU: state: IDLE -> DECODE
    EXU->>EXU: 解析: opcode=Load, rd=x6, rs1=x10, imm=8
    EXU->>RF: raddr1=10
    RF-->>EXU: rdata1=0x80000000
    end

    rect rgb(200, 255, 200)
    Note over EXU,LSU: 阶段3: 执行 + 发起访存 (Execute)
    Note over EXU: state: DECODE -> EXECUTE
    EXU->>EXU: lsu_addr = 0x80000000 + 8 = 0x80000008
    EXU->>LSU: lsu_req=1, lsu_wen=0, lsu_addr=0x80000008
    Note over EXU: state: EXECUTE -> WAIT_LSU
    end

    rect rgb(255, 255, 200)
    Note over LSU,MEM: 阶段4: LSU访存 (Memory Access)
    LSU->>ARB: arvalid=1, araddr=0x80000008
    Note over ARB: state: IDLE -> ARB_LSU
    ARB->>MEM: s_arvalid=1, s_araddr=0x80000008
    MEM-->>ARB: s_arready=1
    Note over MEM: 读取PSRAM (~180周期)
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
    EXU->>EXU: ex_end翻转
    Note over EXU: state: WRITEBACK -> IDLE
    end

    rect rgb(230, 230, 230)
    Note over TOP: 阶段6: PC更新
    EXU-->>TOP: ex_end变化, next_pc=0x30000014
    TOP->>TOP: pc = 0x30000014
    end
""",

    "02_icache_miss_timing": """
sequenceDiagram
    autonumber
    participant TOP as TopModule
    participant IC as ICache
    participant IFU as IFU_AXI
    participant ARB as Arbiter
    participant MEM as Memory/SoC

    Note over TOP: PC = 0x30000010 (首次访问)

    rect rgb(200, 230, 255)
    Note over TOP,MEM: 取指 (Fetch) - ICache未命中
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
    Note over MEM: 从Flash XIP读取 (~750周期)
    MEM-->>ARB: s_rvalid=1, s_rdata=0x00852303
    ARB-->>IFU: m0_rvalid=1, m0_rdata=0x00852303
    Note over ARB: state: ARB_IFU -> IDLE
    IFU-->>IC: mem_rvalid=1, mem_rdata=0x00852303
    Note over IC: 更新Cache并返回数据
    Note over IC: state: REFILL -> IDLE
    IC-->>TOP: cpu_rvalid=1, cpu_rdata=0x00852303
    TOP->>TOP: op_ifu=0x00852303, op_en_ifu=1
    end
""",

    "03_exu_state_machine": """
stateDiagram-v2
    direction LR
    
    [*] --> IDLE: reset
    IDLE --> DECODE: op_en=1
    DECODE --> EXECUTE: 译码完成
    EXECUTE --> WAIT_LSU: Load/Store指令
    WAIT_LSU --> WRITEBACK: lsu_rvalid=1
    WRITEBACK --> IDLE: 写回完成
""",

    "04_icache_state_machine": """
stateDiagram-v2
    [*] --> S_IDLE: reset
    S_IDLE --> S_LOOKUP: cpu_req=1
    S_LOOKUP --> S_IDLE: cache_hit=1
    S_LOOKUP --> S_REFILL: cache_hit=0
    S_REFILL --> S_IDLE: mem_rvalid=1
""",

    "05_ifu_state_machine": """
stateDiagram-v2
    [*] --> IFU_IDLE: reset
    IFU_IDLE --> IFU_WAIT_AR: req=1
    IFU_WAIT_AR --> IFU_WAIT_R: arready=1
    IFU_WAIT_R --> IFU_IDLE: rvalid=1
""",

    "06_arbiter_state_machine": """
stateDiagram-v2
    [*] --> ARB_IDLE: reset
    ARB_IDLE --> ARB_IFU: ifu_req=1
    ARB_IDLE --> ARB_LSU: lsu_req=1
    ARB_IFU --> ARB_IDLE: 事务完成
    ARB_LSU --> ARB_IDLE: 事务完成
""",

    "07_axi_read_timing": """
sequenceDiagram
    participant LSU as LSU_AXI
    participant ARB as Arbiter
    participant SoC as ysyxSoC
    
    Note over LSU,SoC: AXI4-Lite 读事务
    
    rect rgb(255, 240, 200)
    Note over LSU,SoC: AR通道 (读地址)
    LSU->>ARB: arvalid=1, araddr=0x80000008
    ARB->>SoC: s_arvalid=1, s_araddr=0x80000008
    SoC-->>ARB: s_arready=1
    Note over ARB: 地址握手完成
    ARB-->>LSU: m1_arready=1
    LSU->>ARB: arvalid=0
    end
    
    rect rgb(200, 255, 200)
    Note over LSU,SoC: R通道 (读数据)
    LSU->>ARB: rready=1
    Note over SoC: 读取PSRAM (~180周期)
    SoC-->>ARB: s_rvalid=1, s_rdata=0xDEADBEEF
    ARB-->>LSU: m1_rvalid=1, m1_rdata
    Note over LSU: 数据握手完成
    LSU->>ARB: rready=0
    end
"""
}

def mermaid_to_png(diagram_code: str, output_path: str):
    """使用 mermaid.ink 服务将 Mermaid 代码转换为 PNG"""
    # Base64 编码
    encoded = base64.urlsafe_b64encode(diagram_code.encode('utf-8')).decode('utf-8')
    
    # 构建 URL
    url = f"https://mermaid.ink/img/{encoded}?type=png&bgColor=white"
    
    print(f"正在生成: {output_path}")
    
    try:
        # 下载图片
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        with urllib.request.urlopen(req, timeout=30) as response:
            with open(output_path, 'wb') as f:
                f.write(response.read())
        print(f"  ✓ 成功: {output_path}")
        return True
    except Exception as e:
        print(f"  ✗ 失败: {e}")
        return False

def main():
    print("=" * 60)
    print("LW 指令时序图生成器")
    print("=" * 60)
    print(f"输出目录: {OUTPUT_DIR}\n")
    
    success_count = 0
    for name, code in DIAGRAMS.items():
        output_path = os.path.join(OUTPUT_DIR, f"{name}.png")
        if mermaid_to_png(code.strip(), output_path):
            success_count += 1
    
    print(f"\n完成！成功生成 {success_count}/{len(DIAGRAMS)} 个图表")
    print(f"图片保存在: {OUTPUT_DIR}")

if __name__ == "__main__":
    main()
