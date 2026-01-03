#include <amtest.h>

// 直接读取 PS/2 控制器寄存器进行测试
#define PS2_DATA_REG   (*((volatile uint32_t *)0x10011000))
#define PS2_STATUS_REG (*((volatile uint32_t *)0x10011004))

void ps2_test() {
  printf("PS/2 Debug Test\n");
  
  // 先清空 FIFO
  printf("Draining FIFO...\n");
  int drain_count = 0;
  while (drain_count < 32) {
    uint32_t data = PS2_DATA_REG;
    if (data == 0) break;
    printf("  Drained: 0x%x\n", data);
    drain_count++;
  }
  printf("Drained %d items.\n\n", drain_count);
  
  printf("Press keys in NVBoard. Showing raw scancodes:\n");
  printf("(Press 'q' in UART to quit)\n\n");
  
  while (1) {
    // 检查 UART 输入
    uint8_t lsr = *(volatile uint8_t *)0x10000014;  // UART_LSR
    if (lsr & 0x01) {
      char ch = *(volatile uint8_t *)0x10000000;  // UART_RBR
      if (ch == 'q') {
        printf("\nQuit.\n");
        return;
      }
    }
    
    // 读取 PS/2
    uint32_t data = PS2_DATA_REG;
    if (data != 0) {
      printf("RAW: 0x%x ", data);
      
      // 解释扫描码
      if (data == 0xE0) {
        printf("(EXT prefix)");
      } else if (data == 0xF0) {
        printf("(BREAK prefix)");
      } else {
        // 尝试解码
        printf("(make code)");
      }
      printf("\n");
    }
  }
}
