#include "VysyxSoCFull.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <cstring>
#include "sim.h"

extern "C" void flash_init_test_data();
extern "C" void flash_load_program(const char* filename, uint32_t flash_offset);
extern "C" bool npc_request_exit();

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <image>" << std::endl;
        std::cout << "  image: binary to load into Flash at 0x30000000" << std::endl;
        return 0;
    }
    const char* imgPath = argv[1];

    // Initialize flash test data for verification (at 1MB offset)
    flash_init_test_data();

    // Load main program to Flash at offset 0 (XIP address 0x30000000)
    flash_load_program(imgPath, 0);

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
