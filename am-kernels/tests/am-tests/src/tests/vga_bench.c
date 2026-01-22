// VGA 简单显示测试 - 只写入固定颜色，然后等待
#include <amtest.h>

#define SCREEN_W  640
#define SCREEN_H  480

#define VGA_BASE    0x21000000UL
#define VGA_SYNC    (VGA_BASE + 0x04)
#define VGA_FB      (VGA_BASE + 0x08)

// 等待 VSync (帧消隐期)
// 注意: 当前 VGA 控制器没有实现 sync 寄存器读取
// 这里只是预留接口，实际需要硬件支持
static inline void wait_vsync(void) {
  // 简单延时，让 VGA 有时间完成一帧扫描
  // 一帧 = 800*525 = 420000 周期
  for (volatile int i = 0; i < 1000; i++);
}

void vga_bench() {
  printf("========================================\n");
  printf("    VGA Display Test (with sync)\n");
  printf("========================================\n");
  
  volatile uint32_t *fb = (volatile uint32_t *)VGA_FB;
  
  // 写入条纹图案 - 每次只写一小块
  printf("Drawing color bars...\n");
  
  // 红色条 (前 60 行)
  for (int y = 0; y < 60; y++) {
    for (int x = 0; x < SCREEN_W; x++) {
      fb[y * SCREEN_W + x] = 0x00FF0000;
    }
  }
  printf("Red bar done.\n");
  
  // 绿色条
  for (int y = 60; y < 120; y++) {
    for (int x = 0; x < SCREEN_W; x++) {
      fb[y * SCREEN_W + x] = 0x0000FF00;
    }
  }
  printf("Green bar done.\n");
  
  // 蓝色条
  for (int y = 120; y < 180; y++) {
    for (int x = 0; x < SCREEN_W; x++) {
      fb[y * SCREEN_W + x] = 0x000000FF;
    }
  }
  printf("Blue bar done.\n");
  
  // 白色条
  for (int y = 180; y < 240; y++) {
    for (int x = 0; x < SCREEN_W; x++) {
      fb[y * SCREEN_W + x] = 0x00FFFFFF;
    }
  }
  printf("White bar done.\n");
  
  printf("\n========================================\n");
  printf("    Static test complete!\n");
  printf("========================================\n");
  printf("You should see: RED, GREEN, BLUE, WHITE bars\n");
  printf("Lower half should be BLACK\n");
  
  // 无限等待
  printf("\nHolding display...\n");
  int count = 0;
  while (1) {
    for (volatile int i = 0; i < 100000; i++);
    count++;
    if (count % 50 == 0) {
      printf("Still running... %d\n", count);
    }
  }
}
