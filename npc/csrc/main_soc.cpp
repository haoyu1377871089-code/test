#include "VysyxSoCFull.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include "sim.h"

extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr);
extern "C" bool npc_request_exit();

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <image>" << std::endl;
        return 0;
    }
    const char* imgPath = argv[1];

    // Load image to MROM (0x20000000)
    pmem_load_binary(imgPath, 0x20000000);

    if (argc > 2) {
        pmem_load_binary(argv[2], 0x30000000);
    }

    VysyxSoCFull *top = new VysyxSoCFull;
    VerilatedVcdC *tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("build_soc/trace.vcd");

    top->reset = 1;
    top->clock = 0;
    top->externalPins_uart_rx = 1; // Idle high

    int time = 0;
    while (!Verilated::gotFinish() && !npc_request_exit()) {
        if (time > 100) top->reset = 0; // Reset for 100 ticks

        top->clock = !top->clock;
        top->eval();
        tfp->dump(time);
        time++;
    }

    tfp->close();
    delete top;
    return 0;
}
