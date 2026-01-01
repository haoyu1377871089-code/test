/* PSRAM 纯内存测试 - 不使用 printf
 * 
 * 直接用 UART 输出，避免 printf 干扰
 */

#include <am.h>

#define PSRAM_BASE  0x80000000
#define UART_BASE   0x10000000

// 直接 UART 输出一个字符
static void uart_putc(char c) {
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    *uart = c;
}

// 输出字符串
static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

// 输出十六进制
static void uart_hex(uint32_t val) {
    const char *hex = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xf]);
    }
}

int main(const char *args) {
    uart_puts("\n\n=== PSRAM Pure Test (no printf) ===\n");
    
    volatile uint32_t *p0 = (volatile uint32_t *)(PSRAM_BASE + 0x00000);
    volatile uint32_t *p1 = (volatile uint32_t *)(PSRAM_BASE + 0x10000);  // 64KB
    volatile uint32_t *p2 = (volatile uint32_t *)(PSRAM_BASE + 0x100000); // 1MB
    volatile uint32_t *p3 = (volatile uint32_t *)(PSRAM_BASE + 0x200000); // 2MB
    volatile uint32_t *p4 = (volatile uint32_t *)(PSRAM_BASE + 0x3FFFFC); // 4MB-4
    
    // 写入唯一值
    uart_puts("\nWriting...\n");
    *p0 = 0xAA000000;
    *p1 = 0xBB111111;
    *p2 = 0xCC222222;
    *p3 = 0xDD333333;
    *p4 = 0xEE444444;
    
    // 读取验证
    uart_puts("\nReading:\n");
    
    uart_puts("  p0 (0x80000000) = ");
    uart_hex(*p0);
    uart_puts(*p0 == 0xAA000000 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  p1 (0x80010000) = ");
    uart_hex(*p1);
    uart_puts(*p1 == 0xBB111111 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  p2 (0x80100000) = ");
    uart_hex(*p2);
    uart_puts(*p2 == 0xCC222222 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  p3 (0x80200000) = ");
    uart_hex(*p3);
    uart_puts(*p3 == 0xDD333333 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  p4 (0x803ffffc) = ");
    uart_hex(*p4);
    uart_puts(*p4 == 0xEE444444 ? " OK\n" : " FAIL!\n");
    
    // 测试连续写入
    uart_puts("\nConsecutive write test:\n");
    volatile uint32_t *q = (volatile uint32_t *)(PSRAM_BASE + 0x20000);
    q[0] = 0x11111111;
    q[1] = 0x22222222;
    q[2] = 0x33333333;
    q[3] = 0x44444444;
    
    uart_puts("  q[0] = ");
    uart_hex(q[0]);
    uart_puts(q[0] == 0x11111111 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  q[1] = ");
    uart_hex(q[1]);
    uart_puts(q[1] == 0x22222222 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  q[2] = ");
    uart_hex(q[2]);
    uart_puts(q[2] == 0x33333333 ? " OK\n" : " FAIL!\n");
    
    uart_puts("  q[3] = ");
    uart_hex(q[3]);
    uart_puts(q[3] == 0x44444444 ? " OK\n" : " FAIL!\n");
    
    uart_puts("\n=== Test Complete ===\n");
    
    return 0;
}
