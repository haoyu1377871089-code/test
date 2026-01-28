#!/usr/bin/env python3
"""
生成 ICache 未命中的详细时序图
"""

import base64
import urllib.request
import os

OUTPUT_DIR = "/home/hy258/ysyx-workbench/docs/diagrams"
os.makedirs(OUTPUT_DIR, exist_ok=True)

DIAGRAM = """
sequenceDiagram
    autonumber
    participant TOP as TopModule<br/>顶层模块
    participant IC as ICache<br/>指令缓存
    participant IFU as IFU_AXI<br/>取指接口
    participant ARB as Arbiter<br/>总线仲裁
    participant BRG as Bridge<br/>协议桥
    participant SoC as ysyxSoC<br/>片上系统
    participant Flash as Flash XIP<br/>0x30000000

    Note over TOP: PC = 0x30000010<br/>首次访问该地址

    rect rgb(200, 230, 255)
    Note over TOP,IC: 阶段1: CPU发起取指请求
    TOP->>TOP: ifu_req = 1
    TOP->>TOP: ifu_addr = 0x30000010
    TOP->>IC: cpu_req=1, cpu_addr=0x30000010
    Note over IC: state: S_IDLE
    IC->>IC: 锁存地址 req_addr_reg = 0x30000010
    Note over IC: state: S_IDLE -> S_LOOKUP
    end

    rect rgb(255, 200, 200)
    Note over IC: 阶段2: Cache查找 - 未命中!
    Note over IC: state: S_LOOKUP
    IC->>IC: 计算 req_tag = 0x060000
    IC->>IC: 计算 req_index = 0x004
    IC->>IC: 检查 valid[0][4] && tags[0][4]==req_tag
    IC->>IC: 检查 valid[1][4] && tags[1][4]==req_tag
    Note over IC: hit_way0 = 0<br/>hit_way1 = 0<br/>cache_hit = 0 (MISS!)
    IC->>IC: 记录 refill_index = 0x004
    IC->>IC: 记录 refill_tag = 0x060000
    IC->>IC: 选择 refill_way = lru[4] (假设=0)
    Note over IC: state: S_LOOKUP -> S_REFILL
    end

    rect rgb(255, 255, 200)
    Note over IC,IFU: 阶段3: ICache发起内存请求
    Note over IC: state: S_REFILL
    IC->>IC: refill_req_sent = 0
    IC->>IFU: mem_req=1, mem_addr=0x30000010
    IC->>IC: refill_req_sent = 1
    Note over IFU: state: IFU_IDLE
    IFU->>IFU: 锁存地址
    Note over IFU: state: IFU_IDLE -> IFU_WAIT_AR
    IFU->>ARB: arvalid=1, araddr=0x30000010
    end

    rect rgb(230, 255, 230)
    Note over ARB,BRG: 阶段4: 仲裁器授权 + AXI地址握手
    Note over ARB: 检测 ifu_req = m0_arvalid = 1
    Note over ARB: state: ARB_IDLE -> ARB_IFU
    ARB->>ARB: granted_master = IFU
    ARB->>BRG: s_arvalid=1, s_araddr=0x30000010
    BRG->>SoC: AXI4 arvalid=1, araddr=0x30000010
    BRG->>SoC: arlen=0, arsize=2, arburst=01
    SoC-->>BRG: arready=1
    BRG-->>ARB: s_arready=1
    ARB-->>IFU: m0_arready=1
    Note over IFU: AR通道握手完成
    Note over IFU: state: IFU_WAIT_AR -> IFU_WAIT_R
    IFU->>ARB: arvalid=0
    end

    rect rgb(255, 230, 200)
    Note over SoC,Flash: 阶段5: 访问Flash XIP (漫长等待)
    Note over SoC: 地址路由: 0x30000000 -> Flash
    SoC->>Flash: APB读请求
    Note over Flash: QSPI Flash 读取中...<br/>需要约 750 个时钟周期!
    Note over IC: state: S_REFILL (等待中)
    Note over IFU: state: IFU_WAIT_R (等待中)
    Note over ARB: state: ARB_IFU (保持)
    Flash-->>SoC: 返回数据 0x00852303
    end

    rect rgb(200, 255, 200)
    Note over SoC,IFU: 阶段6: 数据返回 - R通道握手
    SoC-->>BRG: rvalid=1, rdata=0x00852303, rresp=OKAY
    BRG-->>ARB: s_rvalid=1, s_rdata=0x00852303
    ARB-->>IFU: m0_rvalid=1, m0_rdata=0x00852303
    IFU->>IFU: 锁存数据 rdata_reg = 0x00852303
    IFU->>IFU: rvalid_out = 1
    Note over IFU: state: IFU_WAIT_R -> IFU_IDLE
    Note over ARB: 检测 m0_rvalid && m0_rready
    Note over ARB: state: ARB_IFU -> ARB_IDLE
    end

    rect rgb(230, 200, 255)
    Note over IC: 阶段7: ICache更新 + 返回数据给CPU
    IFU-->>IC: mem_rvalid=1, mem_rdata=0x00852303
    Note over IC: state: S_REFILL
    IC->>IC: 写入缓存:
    IC->>IC: valid[0][4] = 1
    IC->>IC: tags[0][4] = 0x060000
    IC->>IC: data[0][4] = 0x00852303
    IC->>IC: 更新LRU: lru[4] = 1 (way0刚用过)
    IC->>TOP: cpu_rvalid=1, cpu_rdata=0x00852303
    Note over IC: state: S_REFILL -> S_IDLE
    end

    rect rgb(220, 220, 220)
    Note over TOP: 阶段8: 顶层锁存指令
    TOP->>TOP: ifu_rvalid检测到=1
    TOP->>TOP: op_ifu = 0x00852303
    TOP->>TOP: op_en_ifu = 1
    Note over TOP: 指令 lw x6, 8(x10) 准备送入EXU执行
    end
"""

def mermaid_to_png(diagram_code: str, output_path: str):
    """使用 mermaid.ink 服务将 Mermaid 代码转换为 PNG"""
    encoded = base64.urlsafe_b64encode(diagram_code.encode('utf-8')).decode('utf-8')
    url = f"https://mermaid.ink/img/{encoded}?type=png&bgColor=white"
    
    print(f"正在生成: {output_path}")
    
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        with urllib.request.urlopen(req, timeout=60) as response:
            with open(output_path, 'wb') as f:
                f.write(response.read())
        print(f"✓ 成功生成!")
        return True
    except Exception as e:
        print(f"✗ 失败: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("ICache 未命中详细时序图生成器")
    print("=" * 60)
    
    output_path = os.path.join(OUTPUT_DIR, "icache_miss_detailed.png")
    if mermaid_to_png(DIAGRAM.strip(), output_path):
        print(f"\n图片已保存到: {output_path}")
    else:
        print("\n生成失败，请检查网络连接")
