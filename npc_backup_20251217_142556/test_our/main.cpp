#include "Vtop.h"
#include "verilated.h"
// 下面两行是打开 VCD trace 支持
#include "verilated_vcd_c.h"

#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtop* top = new Vtop;

    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;

    top->trace(tfp, 99);            // 99 表示 trace 深度
    tfp->open("waveform.vcd");      // 输出到 waveform.vcd

    // 仿真主循环
    for (vluint64_t tick = 0; tick < 1000; ++tick) {
        top->clk = !top->clk;
        top->a   = rand() & 1;
        top->b   = rand() & 1;
        top->eval();
        tfp->dump(tick);            // 每个 tick 写一份波形
    }

    // 结束仿真，关闭文件
    tfp->close();
    delete top;
    return 0;
}