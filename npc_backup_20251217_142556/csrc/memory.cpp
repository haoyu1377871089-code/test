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

static inline bool in_pmem(uint32_t addr) {
  return addr >= CONFIG_MBASE && addr < CONFIG_MBASE + CONFIG_MSIZE;
}

extern "C" uint32_t pmem_read(uint32_t raddr) {
  // 设备读优先
  uint32_t devv = devices::read(raddr);
  if (devv != UINT32_MAX) return devv;

  if (in_pmem(raddr) && in_pmem(raddr + 3)) {
    uint32_t offset = raddr - CONFIG_MBASE;
    uint32_t data = 0;
    data |= (uint32_t)pmem[offset];
    data |= (uint32_t)pmem[offset + 1] << 8;
    data |= (uint32_t)pmem[offset + 2] << 16;
    data |= (uint32_t)pmem[offset + 3] << 24;
    return data;
  }
  printf("警告: 读取非法地址 0x%08x\n", raddr);
  return 0;
}

extern "C" void pmem_write(uint32_t waddr, uint32_t wdata, uint8_t wmask) {
  // 设备写优先 - devices::write会处理所有设备地址
  devices::write(waddr, wdata, wmask);
  
  // 检查是否是设备地址范围（简化检查）
  if (waddr >= 0xa0000000 && waddr < 0xa2000000) {
    // 属于设备地址范围，设备模块已处理
    return;
  }

  if (in_pmem(waddr) && in_pmem(waddr + 3)) {
    uint32_t offset = waddr - CONFIG_MBASE;
    for (int i = 0; i < 4; i++) {
      if ((wmask >> i) & 1) {
        pmem[offset + i] = (wdata >> (i * 8)) & 0xff;
      }
    }
    return;
  }
  printf("警告: 写入非法地址 0x%08x, 数据=0x%08x, 掩码=0x%x\n", waddr, wdata, wmask);
}

extern "C" void pmem_load_binary(const char* filename, uint32_t start_addr) {
  // 初始化物理内存和设备
  pmem.assign(CONFIG_MSIZE, 0);
  devices::init();

  FILE* fp = fopen(filename, "rb");
  if (fp == NULL) {
    printf("错误: 无法打开文件 %s\n", filename);
    return;
  }
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (start_addr < CONFIG_MBASE) {
    printf("错误: 起始地址 0x%08x 小于内存基址 0x%08x\n", start_addr, CONFIG_MBASE);
    fclose(fp);
    return;
  }
  uint32_t offset = start_addr - CONFIG_MBASE;
  if (pmem.size() == 0) {
    printf("错误: 内存未初始化\n");
    fclose(fp);
    return;
  }
  if (offset + size > pmem.size()) {
    printf("警告: 文件大小 %ld 字节可能超出内存范围，最大允许: %ld 字节\n", size, pmem.size() - offset);
    size = std::min(size, (long)(pmem.size() - offset));
  }
  size_t bytes_read = fread(&pmem[offset], 1, size, fp);
  if (bytes_read != size) {
    printf("警告: 只读取了 %zu/%ld 字节\n", bytes_read, size);
  }
  fclose(fp);
  printf("成功加载文件 %s 到地址 0x%08x, 大小 %ld 字节\n", filename, start_addr, bytes_read);
}

extern "C" bool npc_request_exit() { return devices::request_exit(); }
extern "C" void npc_set_exit_after_frames(int n) { devices::set_exit_after_frames(n); }

