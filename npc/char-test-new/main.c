#define UART_BASE 0x10000000L
#define UART_TX   0

void c_main() {
  *(volatile char *)(UART_BASE + UART_TX) = 'A';
  while (1);
}
