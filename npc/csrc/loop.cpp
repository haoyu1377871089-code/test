#include "sim.h"
#include "Vtop.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif
#include <cstdio>

#if VM_TRACE
void execute_first_instruction(Vtop *top, uint32_t currentPC, VerilatedVcdC *tfp, uint64_t &sim_time) {
#else
void execute_first_instruction(Vtop *top, uint32_t currentPC, void *tfp, uint64_t &sim_time) {
#endif
    // 设置第一条指令
    top->op = pc_inst[currentPC];
    top->sdop_en = 1;

    // 时钟上升沿
    top->clk = !top->clk;
    top->eval();
#if VM_TRACE
    if (tfp) ((VerilatedVcdC*)tfp)->dump(sim_time++);
#else
    sim_time++;
#endif

    // 时钟下降沿
    top->clk = !top->clk;
    top->eval();
#if VM_TRACE
    if (tfp) ((VerilatedVcdC*)tfp)->dump(sim_time++);
#else
    sim_time++;
#endif

    // 清除指令有效信号
    top->sdop_en = 0;
}

#if VM_TRACE
bool process_one_cycle(Vtop *top, uint32_t &currentPC, bool &sdop_en_state, VerilatedVcdC *tfp, uint64_t &sim_time) {
#else
bool process_one_cycle(Vtop *top, uint32_t &currentPC, bool &sdop_en_state, void *tfp, uint64_t &sim_time) {
#endif
    if (top->rdop_en) {
        currentPC = top->dnpc;
        auto it = pc_inst.find(currentPC);
        if (it != pc_inst.end()) {
            top->op = it->second;
        } else {
            printf("警告: PC=0x%08x 处没有指令\n", currentPC);
            return false;
        }
        top->sdop_en = 1;
        sdop_en_state = true;
    } else if (sdop_en_state) {
        top->sdop_en = 0;
        sdop_en_state = false;
    }

    // 时钟上升沿
    top->clk = !top->clk;
    top->eval();
#if VM_TRACE
    if (tfp) ((VerilatedVcdC*)tfp)->dump(sim_time++);
#else
    sim_time++;
#endif

    bool end_flag = top->end_flag;

    // 时钟下降沿
    top->clk = !top->clk;
    top->eval();
#if VM_TRACE
    if (tfp) ((VerilatedVcdC*)tfp)->dump(sim_time++);
#else
    sim_time++;
#endif

    return !end_flag;
}