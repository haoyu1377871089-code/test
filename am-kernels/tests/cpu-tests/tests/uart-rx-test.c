#include "trap.h"
#include <am.h>
#include <klib.h>
#include <klib-macros.h>

// 简单的 UART RX 测试
int main() {
  printf("UART RX Test - Type something on NVBoard UART terminal...\n");
  printf("Press 'q' to exit\n");
  
  // 检查 UART 是否可用
  bool has_uart = io_read(AM_UART_CONFIG).present;
  if (!has_uart) {
    printf("UART not available!\n");
    return 0;
  }
  
  printf("UART is available, waiting for input...\n");
  
  while (1) {
    char ch = io_read(AM_UART_RX).data;
    if (ch != (char)-1) {
      printf("Received: '%c' (0x%02x)\n", ch >= 32 ? ch : '.', (unsigned char)ch);
      if (ch == 'q' || ch == 'Q') {
        printf("Exiting...\n");
        break;
      }
    }
  }
  
  return 0;
}
