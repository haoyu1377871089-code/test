#include <cstdio>
#include <cstdint>
#include <vector>
#include <cstring>
#include <svdpi.h>
#include <algorithm>
#include "sim.h"
#include "dev/devices.h"

// 物理内存（DRAM 仿真）
static std::vector<uint8_t> pmem;
// Flash 仿真
static std::vector<uint8_t> flash;
// MROM 仿真
static std::vector<uint8_t> mrom;
// SRAM 仿真 (Shadow Memory for DiffTest/Debug)
static std::vector<uint8_t> sram;

static inline bool in_pmem(uint32_t addr) {
  return addr >= CONFIG_MBASE && addr < CONFIG_MBASE + CONFIG_MSIZE;
}

static inline bool in_sram(uint32_t addr) {
  return addr >= CONFIG_SRAM_BASE && addr < CONFIG_SRAM_BASE + CONFIG_SRAM_SIZE;
}

static inline bool in_flash(uint32_t addr) {
  return addr >= CONFIG_FLASH_BASE && addr < CONFIG_FLASH_BASE + CONFIG_FLASH_SIZE;
}

static inline bool in_mrom(uint32_t addr) {
  return addr >= 0x20000000 && addr < 0x20000000 + 4096;
}

// Flash 测试模式数据 - 供测试程序验证
// 这些数据会在仿真初始化时写入 Flash 的特定偏移位置
#define FLASH_TEST_OFFSET  0x00100000  // 测试数据从 1MB 偏移开始 (绝对地址 0x30100000)
#define FLASH_TEST_MAGIC   0xDEADBEEF
#define FLASH_TEST_PATTERN_COUNT 16

// char-test 存储位置
#define FLASH_CHAR_TEST_OFFSET 0x00200000  // 2MB 偏移

static uint32_t flash_test_patterns[FLASH_TEST_PATTERN_COUNT] = {
    0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00,
    0x11111111, 0x22222222, 0x33333333, 0x44444444,
    0x55555555, 0x66666666, 0x77777777, 0x88888888,
    0x99999999, 0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC
};

extern "C" void flash_init_test_data() {
  if (flash.empty()) flash.resize(CONFIG_FLASH_SIZE);
  
  // 写入测试模式数据到 Flash
  for (int i = 0; i < FLASH_TEST_PATTERN_COUNT; i++) {
    uint32_t offset = FLASH_TEST_OFFSET + i * 4;
    uint32_t data = flash_test_patterns[i];
    flash[offset + 0] = (data >> 0) & 0xFF;
    flash[offset + 1] = (data >> 8) & 0xFF;
    flash[offset + 2] = (data >> 16) & 0xFF;
    flash[offset + 3] = (data >> 24) & 0xFF;
  }
  printf("Flash test data initialized at offset 0x%08x (16 patterns)\n", FLASH_TEST_OFFSET);
}

extern "C" void flash_load_program(const char* filename, uint32_t flash_offset) {
  if (flash.empty()) flash.resize(CONFIG_FLASH_SIZE);
  
  FILE* fp = fopen(filename, "rb");
  if (fp == NULL) {
    printf("Flash: 无法打开文件 %s\n", filename);
    return;
  }
  
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  
  if (flash_offset + size > CONFIG_FLASH_SIZE) {
    printf("Flash: 程序太大，超出 Flash 容量\n");
    fclose(fp);
    return;
  }
  
  if (fread(flash.data() + flash_offset, size, 1, fp) != 1) {
    printf("Flash: 读取文件失败\n");
  } else {
    printf("Flash: 已加载 %s 到偏移 0x%08x (%ld 字节)\n", filename, flash_offset, size);
  }
  
  fclose(fp);
}

extern "C" void flash_read(int addr, int *data) {
  if (flash.empty()) flash.resize(CONFIG_FLASH_SIZE);
  
  if (addr >= 0 && addr < CONFIG_FLASH_SIZE) {
      if (addr + 4 <= flash.size()) {
        *data = (uint32_t)flash[addr] |
                ((uint32_t)flash[addr+1] << 8) |
                ((uint32_t)flash[addr+2] << 16) |
                ((uint32_t)flash[addr+3] << 24);
        // printf("Flash read: %08x, data: %08x\n", addr, *data);
        return;
      }
  }
  *data = 0;
  printf("Flash read: %08x, data: 0 (error)\n", addr);
}

extern "C" void mrom_read(int addr, int *data) {
  // printf("MROM read: %08x\n", addr);
  // addr 是绝对地址
  if (in_mrom(addr)) {
    uint32_t offset = addr - 0x20000000;
    if (offset + 4 <= mrom.size()) {
      *data = (uint32_t)mrom[offset] |
              ((uint32_t)mrom[offset+1] << 8) |
              ((uint32_t)mrom[offset+2] << 16) |
              ((uint32_t)mrom[offset+3] << 24);
      return;
    }
  }
  // 默认返回 ebreak 指令 (opcode: 0x00100073)
  *data = 0x00100073; 
}


extern "C" uint32_t pmem_read(uint32_t raddr) {
  // 设备读优先
  uint32_t devv = devices::read(raddr);
  if (devv != UINT32_MAX) return devv;

  if (in_pmem(raddr) && in_pmem(raddr + 3)) {
    // 确保 pmem 已初始化
    if (pmem.empty()) pmem.resize(CONFIG_MSIZE);
    uint32_t offset = raddr - CONFIG_MBASE;
    uint32_t data = 0;
    data |= (uint32_t)pmem[offset];
    data |= (uint32_t)pmem[offset + 1] << 8;
    data |= (uint32_t)pmem[offset + 2] << 16;
    data |= (uint32_t)pmem[offset + 3] << 24;
    return data;
  }

  if (in_sram(raddr)) {
    // SRAM 尚未初始化时自动调整大小
    if (sram.empty()) sram.resize(CONFIG_SRAM_SIZE);
    uint32_t offset = raddr - CONFIG_SRAM_BASE;
    if (offset + 4 <= sram.size()) {
      uint32_t data = 0;
      data |= (uint32_t)sram[offset];
      data |= (uint32_t)sram[offset + 1] << 8;
      data |= (uint32_t)sram[offset + 2] << 16;
      data |= (uint32_t)sram[offset + 3] << 24;
      return data;
    }
  }

  printf("警告: 读取非法地址 0x%08x\n", raddr);
  return 0;
}

extern "C" void pmem_write(uint32_t waddr, uint32_t wdata, uint8_t wmask) {

  // 设备写优先 - devices::write会处理所有设备地址
  devices::write(waddr, wdata, wmask);
  
  // 检查是否是设备地址范围（简化检查）
  // 包括: 设备区域 0xa0000000-0xa2000000, UART 0x10000000-0x10001000, SPI 0x10001000-0x10002000
  if ((waddr >= 0xa0000000 && waddr < 0xa2000000) || (waddr >= 0x10000000 && waddr < 0x10002000)) {
    // 属于设备地址范围，设备模块已处理
    return;
  }

  if (in_pmem(waddr) && in_pmem(waddr + 3)) {
    // 确保 pmem 已初始化
    if (pmem.empty()) pmem.resize(CONFIG_MSIZE);
    uint32_t offset = waddr - CONFIG_MBASE;
    for (int i = 0; i < 4; i++) {
      if ((wmask >> i) & 1) {
        pmem[offset + i] = (wdata >> (i * 8)) & 0xff;
      }
    }
    return;
  }

  if (in_sram(waddr)) {
    // SRAM 尚未初始化时自动调整大小
    if (sram.empty()) sram.resize(CONFIG_SRAM_SIZE);
    uint32_t offset = waddr - CONFIG_SRAM_BASE;
    if (offset + 4 <= sram.size()) {
      for (int i = 0; i < 4; i++) {
        if ((wmask >> i) & 1) {
          sram[offset + i] = (wdata >> (i * 8)) & 0xff;
        }
      }
      return;
    }
  }
  printf("警告: 写入非法地址 0x%08x, 数据=0x%08x, 掩码=0x%x\n", waddr, wdata, wmask);
}

extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr) {
  // 初始化物理内存和设备
  if (pmem.empty()) pmem.assign(CONFIG_MSIZE, 0);
  if (flash.empty()) flash.assign(CONFIG_FLASH_SIZE, 0);
  if (mrom.empty()) mrom.assign(4096, 0);
  devices::init();

  FILE* fp = fopen(filename, "rb");
  if (fp == NULL) {
    printf("错误: 无法打开文件 %s\n", filename);
    return;
  }
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);

  if (in_flash(start_addr)) {
      uint32_t offset = start_addr - CONFIG_FLASH_BASE;
      if (offset + size > CONFIG_FLASH_SIZE) {
          printf("错误: 镜像大小超过 Flash 容量\n");
          fclose(fp);
          return;
      }
      if (fread(flash.data() + offset, size, 1, fp) != 1) {
          printf("错误: 读取文件失败\n");
      }
      printf("已加载镜像到 Flash: %s (0x%08x)\n", filename, start_addr);
  } else if (in_pmem(start_addr)) {
      uint32_t offset = start_addr - CONFIG_MBASE;
      if (offset + size > CONFIG_MSIZE) {
          printf("错误: 镜像大小超过内存容量\n");
          fclose(fp);
          return;
      }
      if (fread(pmem.data() + offset, size, 1, fp) != 1) {
          printf("错误: 读取文件失败\n");
      }
      printf("已加载镜像到 PMEM: %s (0x%08x)\n", filename, start_addr);
  } else if (in_mrom(start_addr)) {
      uint32_t offset = start_addr - 0x20000000;
      if (size > 1024 * 1024) { // Larger than 1MB
          fseek(fp, 0x11000000, SEEK_SET); // Skip the gap (0x20000000 - 0x0f000000)
          size -= 0x11000000;
          printf("检测到巨型镜像，跳过空洞。实际加载大小: %ld 字节\n", size);
      }
      if (offset + size > mrom.size()) {
          mrom.resize(offset + size);
      }
      if (fread(mrom.data() + offset, size, 1, fp) != 1) {
          printf("错误: 读取文件失败\n");
      }
      printf("已加载镜像到 MROM: %s (0x%08x)\n", filename, start_addr);
  } else {
      printf("错误: 起始地址 0x%08x 不在 Flash, MROM 或内存范围内\n", start_addr);
  }
  fclose(fp);
}

extern "C" bool npc_request_exit() { return devices::request_exit(); }
extern "C" void npc_set_exit_after_frames(int n) { devices::set_exit_after_frames(n); }

extern "C" void npc_trap(int exit_code) {
  if (exit_code == 0) {
    printf("HIT GOOD TRAP\n");
  } else {
    printf("HIT BAD TRAP (code = %d)\n", exit_code);
  }
  devices::force_exit();
}

