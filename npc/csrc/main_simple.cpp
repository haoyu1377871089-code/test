#include "VysyxSoCFull.h"
#include "verilated.h"
#include <iostream>
#include <cstring>

extern "C" void flash_load_program(const char* filename, uint32_t flash_offset);
extern "C" bool npc_request_exit();
extern "C" void npc_set_exit_after_frames(int n);

static int uart_state = 0;
static int uart_counter = 0;
static int uart_data = 0;
static int uart_last_tx = 1;
static const int UART_BIT_CYCLES = 16;

void uart_tick(int tx) {
    if (uart_state == 0) {
        if (uart_last_tx == 1 && tx == 0) {
            uart_state = 1;
            uart_counter = UART_BIT_CYCLES + UART_BIT_CYCLES / 2;
            uart_data = 0;
        }
    } else if (uart_state >= 1 && uart_state <= 8) {
        uart_counter--;
        if (uart_counter == 0) {
            uart_data |= (tx << (uart_state - 1));
            uart_state++;
            uart_counter = UART_BIT_CYCLES;
        }
    } else if (uart_state == 9) {
        uart_counter--;
        if (uart_counter == 0) {
            if (tx == 1) {
                char c = (char)uart_data;
                if (c >= 32 && c < 127) std::cout << c << std::flush;
                else if (c == '\n') std::cout << std::endl;
            }
            uart_state = 0;
        }
    }
    uart_last_tx = tx;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    
    const char* imgPath = nullptr;
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-b") == 0 || strcmp(argv[i], "--no-nvboard") == 0) {
            // Ignore
        } else if (argv[i][0] != '-') {
            imgPath = argv[i];
        }
    }
    
    if (imgPath == nullptr) {
        std::cout << "Usage: " << argv[0] << " [options] <image.bin>" << std::endl;
        std::cout << "  -b, --no-nvboard    Run without NVBoard" << std::endl;
        return 0;
    }
    
    npc_set_exit_after_frames(0);
    flash_load_program(imgPath, 0);
    
    VysyxSoCFull *top = new VysyxSoCFull;
    
    top->reset = 1;
    top->clock = 0;
    
    uint64_t time = 0;
    std::cout << "Starting simulation..." << std::endl;
    
    while (!Verilated::gotFinish() && !npc_request_exit()) {
        if (time > 100) top->reset = 0;
        
        top->clock = !top->clock;
        top->eval();
        
        if (top->clock && time > 200) {
            uart_tick(top->externalPins_uart_tx);
        }
        
        time++;
        
        if (time % 10000000 == 0) {
            std::cout << "[PROGRESS] Time: " << time << std::endl;
        }
    }
    
    std::cout << "Simulation finished after " << time << " cycles." << std::endl;
    delete top;
    return 0;
}
