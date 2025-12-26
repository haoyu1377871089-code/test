#define UART_BASE 0x10000000L
#define UART_TX   0

void _start() {
  *(volatile char *)(UART_BASE + UART_TX) = 'A';
  // 按照题目要求，可以尝试不加换行符，或者加上。
  // 为了让输出更容易看到（防止缓冲问题），我们也可以加个死循环防止程序跑飞
  while (1);
}
