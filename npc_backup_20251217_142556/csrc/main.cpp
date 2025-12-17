#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <vector>
#include <cstdint>
#include <string>
#include <unistd.h>
// 提前定义 Area 以满足 amdev.h 的 NET_RX/NET_TX 等依赖
typedef struct { void *start, *end; } Area;
#include "amdev.h"
#include "sim.h"

extern "C" uint32_t pmem_read(uint32_t raddr);
extern "C" void pmem_write(uint32_t waddr, uint32_t wdata, uint8_t wmask);
extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr);
extern "C" bool npc_request_exit();
extern "C" void npc_set_exit_after_frames(int n);

#define VGACTL_ADDR 0xa0000100
#define SYNC_ADDR   (VGACTL_ADDR + 4)
#define FB_ADDR     0xa1000000
#define KBD_ADDR    0xa0000060

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
#if VM_TRACE
    Verilated::traceEverOn(true);
#else
    Verilated::traceEverOn(false);
#endif

    // 解析参数：检测 --kbd-demo，查找第一个非选项作为镜像路径
    std::vector<std::string> args;
    for (int i = 1; i < argc; i++) args.emplace_back(argv[i]);
    bool kbd_demo = false;
    std::string imgPath;
    int exit_frames_cli = -1;
    for (const auto &a : args) {
        if (a == "--kbd-demo") kbd_demo = true;
        else if (a.rfind("--exit-frames=", 0) == 0) {
            exit_frames_cli = std::stoi(a.substr(strlen("--exit-frames=")));
        }
        else if (!a.empty() && a[0] != '-') { imgPath = a; }
    }
    if (exit_frames_cli > 0) {
        npc_set_exit_after_frames(exit_frames_cli);
        std::cout << "命令行设置自动退出帧数: " << exit_frames_cli << std::endl;
    }

    if (kbd_demo) {
        std::cout << "键盘演示模式：按键会打印AM键码，ESC退出" << std::endl;
        pmem_load_binary("/dev/null", CONFIG_MBASE);
        while (true) {
            uint32_t code = pmem_read(KBD_ADDR);
            if (code) {
                bool down = (code & 0x8000u) != 0;
                uint32_t keycode = code & 0x7fffu;
                std::cout << (down ? "DOWN " : "UP   ") << keycode << std::endl;
                if (down && keycode == AM_KEY_ESCAPE) break;
            } else {
                usleep(10000);
            }
        }
        return 0;
    }

    if (imgPath.empty()) {
        std::cout << "未指定程序文件，进入VGA演示模式" << std::endl;
        pmem_load_binary("/dev/null", CONFIG_MBASE);
        uint32_t wh = pmem_read(VGACTL_ADDR);
        uint32_t w = (wh >> 16) & 0xffff;
        uint32_t h = (wh >> 0) & 0xffff;
        for (uint32_t y = 0; y < h; y++) {
            for (uint32_t x = 0; x < w; x++) {
                uint8_t r = (x * 255) / (w ? w : 1);
                uint8_t g = (y * 255) / (h ? h : 1);
                uint8_t b = ((x + y) * 255) / ((w + h) ? (w + h) : 1);
                uint32_t px = (r << 16) | (g << 8) | b;
                pmem_write(FB_ADDR + ((y * w + x) * 4), px, 0xF);
            }
        }
        // 触发一次同步刷新，让 SDL 窗口显示渐变
        pmem_write(SYNC_ADDR, 1, 0xF);
        std::cout << "已在 SDL 窗口显示演示渐变帧" << std::endl;
        return 0;
    }

    std::cout << "加载程序文件: " << imgPath << std::endl;

    // 读取并构建指令映射
    auto programData = readBinaryFile(imgPath);
    buildInstructionMap(programData);

    // 创建顶层模块与波形
    Vtop *top = new Vtop;
    VerilatedVcdC *tfp = nullptr;
#if VM_TRACE
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("./build/dump.vcd");
#endif

    // 加载镜像到内存
    loadImageToMemory(imgPath, CONFIG_MBASE);

    // 初始化仿真状态
    uint64_t sim_time = 0;
    top->rst = 1;
    top->clk = 0;
    top->op = 0;
    top->sdop_en = 0;

    for (int i = 0; i < 5; i++) {
        top->clk = !top->clk; top->eval();
#if VM_TRACE
        if (tfp) tfp->dump(sim_time++);
#else
        sim_time++;
#endif
        top->clk = !top->clk; top->eval();
#if VM_TRACE
        if (tfp) tfp->dump(sim_time++);
#else
        sim_time++;
#endif
    }

    top->rst = 0; top->eval();
#if VM_TRACE
    if (tfp) tfp->dump(sim_time++);
#else
    sim_time++;
#endif

    uint32_t currentPC = CONFIG_MBASE;
    bool sdop_en_state = false;

    std::cout << "开始程序仿真..." << std::endl;

    // 首条指令
    execute_first_instruction(top, currentPC, tfp, sim_time);

    bool running = true;
    while (running) {
        running = process_one_cycle(top, currentPC, sdop_en_state, tfp, sim_time);
        if (!running) break;
        if (npc_request_exit()) {
            std::cout << "收到自动退出请求（帧数达到阈值），结束仿真" << std::endl;
            break;
        }
    }

    std::cout << "仿真完成" << std::endl;

    if (top->exit_code == 0) {
        printf("\033[1;32mHIT GOOD TRAP\033[0m at pc = 0x%08x\n", currentPC);
    } else {
        printf("\033[1;31mHIT BAD TRAP\033[0m code = %d at pc = 0x%08x\n", top->exit_code, currentPC);
    }

    int retcode = (top->exit_code == 0) ? 0 : 1;

#if VM_TRACE
    if (tfp) tfp->close();
    delete tfp;
#endif
    delete top;
    return retcode;
}
