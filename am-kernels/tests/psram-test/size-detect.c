/* PSRAM 大小检测
 * 
 * 检测 PSRAM 的实际大小
 */

#include <am.h>

#define PSRAM_BASE  0x80000000
#define UART_BASE   0x10000000

static void uart_putc(char c) {
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    *uart = c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_hex(uint32_t val) {
    const char *hex = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xf]);
    }
}

int main(const char *args) {
    uart_puts("\n\n=== PSRAM Size Detection ===\n\n");
    
    volatile uint32_t *base = (volatile uint32_t *)PSRAM_BASE;
    
    // 在基址写入一个魔数
    *base = 0xDEADBEEF;
    uart_puts("Wrote 0xDEADBEEF to base (0x80000000)\n\n");
    
    // 检测各个偏移是否会和基址别名
    uint32_t offsets[] = {
        0x00001000,   // 4KB
        0x00002000,   // 8KB
        0x00004000,   // 16KB
        0x00008000,   // 32KB
        0x00010000,   // 64KB
        0x00020000,   // 128KB
        0x00040000,   // 256KB
        0x00080000,   // 512KB
        0x00100000,   // 1MB
        0x00200000,   // 2MB
        0x00400000,   // 4MB (out of range for 4MB chip)
    };
    
    for (int i = 0; i < 11; i++) {
        uint32_t offset = offsets[i];
        volatile uint32_t *ptr = (volatile uint32_t *)(PSRAM_BASE + offset);
        
        // 写入不同的值
        *ptr = 0xCAFE0000 + i;
        
        // 检查基址是否被修改
        uint32_t base_val = *base;
        
        uart_puts("Offset ");
        uart_hex(offset);
        uart_puts(": wrote ");
        uart_hex(0xCAFE0000 + i);
        uart_puts(", base now = ");
        uart_hex(base_val);
        
        if (base_val == (uint32_t)(0xCAFE0000 + i)) {
            uart_puts(" <- ALIASED! (PSRAM size = ");
            uart_hex(offset);
            uart_puts(")\n");
            break;
        } else {
            uart_puts(" OK\n");
        }
        
        // 恢复基址
        *base = 0xDEADBEEF;
    }
    
    uart_puts("\n=== Detection Complete ===\n");
    
    return 0;
}
