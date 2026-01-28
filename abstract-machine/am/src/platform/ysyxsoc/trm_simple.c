// trm_simple.c - 最简化的 TRM，用于快速仿真测试
// 跳过所有 UART 初始化和调试输出

#include <am.h>
#include <klib-macros.h>

extern char _heap_start;
extern char _heap_end;
int main(const char *args);

// MAINARGS 支持
static volatile const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER);

// Heap 在 PSRAM 中
Area heap = RANGE(&_heap_start, &_heap_end);

#define UART_BASE 0x10000000L
#define UART_TX   0
#define UART_LSR  (5 * 4)

// 简化的 putch：只检查一次 UART 状态
void putch(char ch) {
  *(volatile uint8_t *)(UART_BASE + UART_TX) = ch;
}

void halt(int code) {
  asm volatile("ebreak");
  while (1);
}

extern char _data_load_addr;
extern char _data;
extern char _edata;
extern char _bss_start;
extern char _bss_end;

// 极简初始化：拷贝数据段，清零 BSS，然后调用 main
void _trm_init() {
  // 拷贝数据段（从 Flash 到 PSRAM）
  uint32_t *src = (uint32_t *)&_data_load_addr;
  uint32_t *dst = (uint32_t *)&_data;
  uint32_t *end = (uint32_t *)&_edata;
  while (dst < end) { *dst++ = *src++; }
  
  // 清零 BSS 段
  dst = (uint32_t *)&_bss_start;
  end = (uint32_t *)&_bss_end;
  while (dst < end) { *dst++ = 0; }
  
  // 直接调用 main
  int ret = main((const char *)mainargs);
  halt(ret);
}
