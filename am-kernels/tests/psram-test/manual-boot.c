/* 最简 SRAM bootloader 测试 */
/* 这个程序运行在 Flash 中，手动拷贝代码到 SRAM 并跳转 */

#include <stdint.h>

#define UART_BASE   0x10000000
#define SRAM_BASE   0x0f000000

// 最简 UART 输出
static inline void uart_putc(char c) {
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    while (!(uart[5*4] & 0x20));  // wait THRE
    uart[0] = c;
}

static inline void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static inline void uart_hex(uint32_t val) {
    const char hex[] = "0123456789abcdef";
    uart_putc('0'); uart_putc('x');
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(val >> i) & 0xf]);
}

// 要拷贝到 SRAM 并执行的测试代码
// 放在一个单独的函数中，我们手动拷贝它
__attribute__((noinline, section(".mytest")))
void test_in_sram(void) {
    // 这段代码会被拷贝到 SRAM 并在那里执行
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    
    const char msg[] = "Hello from SRAM!\n";
    for (int i = 0; msg[i]; i++) {
        while (!(uart[5*4] & 0x20));
        uart[0] = msg[i];
    }
    
    // 无限循环（作为结束标志）
    while(1);
}

// 标记结束
__attribute__((noinline, section(".mytest_end")))
void test_end_marker(void) {}

int main(const char *args) {
    uart_puts("\n=== Manual SRAM Boot Test ===\n");
    
    // 获取要拷贝的代码地址
    extern void test_in_sram(void);
    extern void test_end_marker(void);
    
    uint32_t src = (uint32_t)test_in_sram;
    uint32_t end = (uint32_t)test_end_marker;
    uint32_t dst = SRAM_BASE;
    uint32_t size = end - src;
    
    uart_puts("Source: "); uart_hex(src); uart_putc('\n');
    uart_puts("End:    "); uart_hex(end); uart_putc('\n');
    uart_puts("Size:   "); uart_hex(size); uart_putc('\n');
    uart_puts("Dest:   "); uart_hex(dst); uart_putc('\n');
    
    // 拷贝代码
    uart_puts("Copying code...\n");
    volatile uint32_t *s = (volatile uint32_t *)src;
    volatile uint32_t *d = (volatile uint32_t *)dst;
    for (uint32_t i = 0; i < (size + 3) / 4; i++) {
        d[i] = s[i];
    }
    
    // 验证拷贝
    uart_puts("Verifying...\n");
    int ok = 1;
    for (uint32_t i = 0; i < (size + 3) / 4; i++) {
        if (d[i] != s[i]) {
            uart_puts("Mismatch at offset "); uart_hex(i*4); uart_putc('\n');
            ok = 0;
            break;
        }
    }
    
    if (!ok) {
        uart_puts("Copy verification FAILED!\n");
        return 1;
    }
    
    uart_puts("Copy verified OK!\n");
    
    // 测试 fence.i 之前
    uart_puts("Before fence.i\n");
    
    // 内存屏障
    asm volatile ("fence.i");
    
    // 测试 fence.i 之后
    uart_puts("After fence.i\n");
    
    // 跳转到 SRAM
    uart_puts("Jumping to SRAM...\n");
    void (*func)(void) = (void (*)(void))dst;
    func();
    
    // 不应该执行到这里
    uart_puts("ERROR: Returned from SRAM!\n");
    return 1;
}
