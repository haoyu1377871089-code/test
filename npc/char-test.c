#define UART_BASE 0x10000000L
#define UART_TX   0

__attribute__((naked)) void _start() {
  asm volatile("li sp, 0x90000000"); // Set SP to a safe area (e.g. PSRAM/SDRAM)
  
  *(volatile char *)(UART_BASE + UART_TX) = 'A';
  *(volatile char *)(UART_BASE + UART_TX) = '\n';
  while (1);
}
