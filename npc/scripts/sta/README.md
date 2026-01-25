# 时序分析 (STA)

**零基础入门**：综合与 STA 的整体思路、每个文件在做什么、修改原因，见  
**[《综合与时序分析学习讲义》](../../docs/综合与时序分析学习讲义.md)**。

## 运行方式

```bash
# 在 npc/scripts/sta 下
./run_sta.sh
```

- **有 OpenSTA**：执行 `run_sta.tcl`，报告写入 `sta_report.log`  
- **无 OpenSTA**：运行 `estimate_timing.sh`，估算结果写入 `sta_estimate.log`

## 安装 OpenSTA（可选）

```bash
sudo apt install opensta
```

安装后 `run_sta.sh` 会自动走 OpenSTA 流程。

## 输入文件

| 文件 | 说明 |
|------|------|
| `yosys_gates.lib` | Yosys 通用门 liberty（占位延时，用于 OpenSTA） |
| `constraints.sdc` | 时钟与约束（`create_clock -period 10 [get_ports clock]`） |
| `run_sta.tcl` | OpenSTA 脚本 |
| `../synth_output/ysyx_00000000_structural.v` | 结构网表（由 `scripts/synth.ys` 中 `write_verilog -noexpr` 生成） |

## 时序估算（无 OpenSTA）

`estimate_timing.sh` 根据 Yosys `stat` 的单元数与假定组合深度、门延时，估算最高频率，例如：

- 组合深度 35 级，门延时 0.1ns，FF clk-to-Q 0.05ns
- 关键路径约 3.55 ns → 约 282 MHz

精确结果需 OpenSTA + 实际工艺 liberty。
