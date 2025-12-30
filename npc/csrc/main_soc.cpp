#include "VysyxSoCFull.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <cstring>
#include "sim.h"

extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr);
extern "C" void flash_init_test_data();
extern "C" void flash_load_program(const char* filename, uint32_t flash_offset);
extern "C" bool npc_request_exit();

// char-test 在 Flash 中的偏移地址
#define FLASH_CHAR_TEST_OFFSET 0x00200000

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <image> [flash_program]" << std::endl;
        std::cout << "  flash_program: optional binary to load into Flash at 2MB offset" << std::endl;
        return 0;
    }
    const char* imgPath = argv[1];

    // Load image to MROM (0x20000000)
    pmem_load_binary(imgPath, 0x20000000);

    // Initialize flash test data for verification
    flash_init_test_data();

    // 加载额外的程序到 Flash
    if (argc > 2) {
        flash_load_program(argv[2], FLASH_CHAR_TEST_OFFSET);
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
