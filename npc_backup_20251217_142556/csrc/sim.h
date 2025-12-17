#pragma once
#include <cstdint>
#include <map>
#include <vector>
#include <string>

// 统一的设备/MMIO 常量
static constexpr uint32_t SERIAL_PORT = 0xa00003f8;
static constexpr uint32_t RTC_ADDR    = 0xa0000048;
static constexpr uint32_t KBD_ADDR    = 0xa0000060;
static constexpr uint32_t VGACTL_ADDR = 0xa0000100;
static constexpr uint32_t SYNC_ADDR   = VGACTL_ADDR + 4;
static constexpr uint32_t FB_ADDR     = 0xa1000000;

// 仿真内存基址与大小
static constexpr uint32_t CONFIG_MBASE = 0x80000000;
static constexpr uint32_t CONFIG_MSIZE = 128 * 1024 * 1024;

// 来自 program.cpp 的全局指令映射
extern std::map<uint32_t, uint32_t> pc_inst;

// 程序与镜像处理（program.cpp）
std::vector<uint8_t> readBinaryFile(const std::string &filename);
void buildInstructionMap(const std::vector<uint8_t> &program);
void loadImageToMemory(const std::string &filename, uint32_t start_addr);

// 来自 memory.cpp 的 DPI-C 接口
extern "C" uint32_t pmem_read(uint32_t raddr);
extern "C" void pmem_write(uint32_t waddr, uint32_t wdata, uint8_t wmask);
extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr);
extern "C" bool npc_request_exit();
extern "C" void npc_set_exit_after_frames(int n);

// 来自 loop.cpp 的仿真驱动接口
struct Vtop;
#if VM_TRACE
class VerilatedVcdC;
void execute_first_instruction(Vtop *top, uint32_t currentPC, VerilatedVcdC *tfp, uint64_t &sim_time);
bool process_one_cycle(Vtop *top, uint32_t &currentPC, bool &sdop_en_state, VerilatedVcdC *tfp, uint64_t &sim_time);
#else
void execute_first_instruction(Vtop *top, uint32_t currentPC, void *tfp, uint64_t &sim_time);
bool process_one_cycle(Vtop *top, uint32_t &currentPC, bool &sdop_en_state, void *tfp, uint64_t &sim_time);
#endif