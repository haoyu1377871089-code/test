#pragma once
#include <cstdint>

// 仿真内存配置常量
static constexpr uint32_t CONFIG_MBASE = 0x80000000;
static constexpr uint32_t CONFIG_MSIZE = 128 * 1024 * 1024;
static constexpr uint32_t CONFIG_FLASH_BASE = 0x30000000;
static constexpr uint32_t CONFIG_FLASH_SIZE = 16 * 1024 * 1024;
static constexpr uint32_t CONFIG_SRAM_BASE = 0x0f000000;
static constexpr uint32_t CONFIG_SRAM_SIZE = 8 * 1024;

// 来自 memory.cpp 的 DPI-C 接口
extern "C" uint32_t pmem_read(uint32_t raddr);
extern "C" void pmem_write(uint32_t waddr, uint32_t wdata, uint8_t wmask);
extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr);
extern "C" bool npc_request_exit();
extern "C" void npc_set_exit_after_frames(int n);
