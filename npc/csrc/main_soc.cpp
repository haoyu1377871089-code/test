#include "VysyxSoCFull.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <cstring>
#include <nvboard.h>
#include <signal.h>

extern "C" void flash_init_test_data();
extern "C" void flash_load_program(const char* filename, uint32_t flash_offset);
extern "C" bool npc_request_exit();
extern "C" void npc_set_exit_after_frames(int n);

// NVBoard's UART divisor counter - set to large value to disable NVBoard UART sampling
extern int16_t uart_divisor_cnt;

// NVBoard auto-generated function declaration
void nvboard_bind_all_pins(VysyxSoCFull* top);

static volatile bool sig_exit = false;
void sigint_handler(int) { sig_exit = true; }

// Simple UART receiver state
static int uart_state = 0;    // 0=idle, 1-8=receiving bits, 9=stop bit
static int uart_counter = 0;
static int uart_data = 0;
static int uart_last_tx = 1;
static int uart_char_count = 0;
// UART 16550: baud = clock / (16 * divisor)
// With divisor = 1, each bit takes 16 clock cycles
// We sample in the middle of each bit
static const int UART_BIT_CYCLES = 16;

void uart_tick(int tx) {
    if (uart_state == 0) {
        // Idle, wait for start bit (falling edge)
        if (uart_last_tx == 1 && tx == 0) {
            uart_state = 1;
            // Wait 1.5 bit times to sample first data bit at its center
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
            // Stop bit, output character
            if (tx == 1) {
                char c = (char)uart_data;
                if (c >= 32 && c < 127) {
                    std::cout << c << std::flush;
                } else if (c == '\n') {
                    std::cout << std::endl;
                } else if (c == '\r') {
                    // ignore
                } else {
                    std::cout << "[0x" << std::hex << (int)(unsigned char)c << std::dec << "]" << std::flush;
                }
                uart_char_count++;
            }
            uart_state = 0;
        }
    }
    uart_last_tx = tx;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    // Parse command line arguments
    bool no_gui = false;
    const char* imgPath = nullptr;
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-n") == 0 || strcmp(argv[i], "--no-gui") == 0) {
            no_gui = true;
        } else if (argv[i][0] != '-') {
            imgPath = argv[i];
        }
    }

    if (imgPath == nullptr) {
        std::cout << "Usage: " << argv[0] << " [options] <image>" << std::endl;
        std::cout << "  image: binary to load into Flash at 0x30000000" << std::endl;
        std::cout << "Options:" << std::endl;
        std::cout << "  -n, --no-gui    Disable NVBoard GUI window" << std::endl;
        return 0;
    }

    // Disable auto-exit after frames (0 means run forever)
    npc_set_exit_after_frames(0);
    signal(SIGINT, sigint_handler);
    signal(SIGTERM, sigint_handler);

    // Initialize flash test data for verification (at 1MB offset)
    flash_init_test_data();

    // Load main program to Flash at offset 0 (XIP address 0x30000000)
    flash_load_program(imgPath, 0);

    VysyxSoCFull *top = new VysyxSoCFull;
    VerilatedVcdC *tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("build_soc/trace.vcd");

    // Initialize NVBoard (unless --no-gui)
    if (!no_gui) {
        nvboard_bind_all_pins(top);
        nvboard_init();
        
        // Disable NVBoard's UART sampling to prevent duplicate character output
        // We use our own uart_tick() for stdout output
        uart_divisor_cnt = 32767;  // Set to max int16_t to effectively disable
    }

    top->reset = 1;
    top->clock = 0;
    // Note: externalPins_uart_rx is controlled by NVBoard via pin_poke

    uint64_t time = 0;
    std::cout << "Starting simulation loop..." << std::endl;
    while (!Verilated::gotFinish() && !npc_request_exit() && !sig_exit) {
        if (time > 100) top->reset = 0; // Reset for 100 ticks

        top->clock = !top->clock;
        top->eval();
        
        // Capture UART TX output (on clock rising edge, after reset)
        // This outputs to stdout for console/pipe usage
        if (top->clock && time > 200) {
            uart_tick(top->externalPins_uart_tx);
        }
        
        // NVBoard update is disabled to prevent duplicate UART output
        // NVBoard's tx_receive() would cause characters to print twice
        // TODO: If VGA/keyboard needed, modify NVBoard to disable UART or use separate flag
        // if (time > 5000000 && time % 1000 == 0) {
        //     nvboard_update();
        // }
        
        if (time < 50000) tfp->dump(time);  // 只保存前50000周期（足够测试）
        time++;
        
        if (time % 10000000 == 0) {
            std::cout << "Time: " << time 
                      << " VGA: valid=" << (int)top->externalPins_vga_valid
                      << " hsync=" << (int)top->externalPins_vga_hsync
                      << " vsync=" << (int)top->externalPins_vga_vsync
                      << " R=" << (int)top->externalPins_vga_r
                      << " G=" << (int)top->externalPins_vga_g
                      << " B=" << (int)top->externalPins_vga_b
                      << std::endl;
        }
    }
    
    std::cout << "Exiting: gotFinish=" << Verilated::gotFinish() 
              << ", request_exit=" << npc_request_exit() 
              << ", uart_chars=" << uart_char_count << std::endl;

    if (!no_gui) {
        nvboard_quit();
    }
    tfp->close();
    delete top;
    return 0;
}
