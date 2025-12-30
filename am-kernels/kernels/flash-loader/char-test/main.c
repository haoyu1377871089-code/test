// char-test: 从 SRAM 运行的简单测试程序
// 通过 UART 输出 "Hello from SRAM!\n"

#define UART_BASE 0x10000000L
#define UART_TX   0
#define UART_LSR  (5 * 4)

static void uart_putc(char ch) {
    while ((*(volatile char *)(UART_BASE + UART_LSR) & 0x20) == 0);
    *(volatile char *)(UART_BASE + UART_TX) = ch;
}

static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

void c_main() {
    uart_puts("Hello from SRAM!\n");
    uart_puts("char-test loaded from Flash successfully!\n");
    
    // 正常结束
    asm volatile("li a0, 0");  // exit code = 0
    asm volatile("ebreak");
    while (1);
}
