#pragma once
#include <cstdint>

// 设备模块：统一处理外设 MMIO（VGA/键盘/RTC/串口）
namespace devices {
  // 初始化设备（分辨率、SDL、键盘线程、自动退出帧数）
  void init();

  // MMIO 读/写总入口
  uint32_t read(uint32_t addr);
  void write(uint32_t addr, uint32_t data, uint8_t wmask);

  // 自动退出控制
  bool request_exit();
  void set_exit_after_frames(int n);
}