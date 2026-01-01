/* PSRAM 4MB 完整测试 (从 SRAM 执行)
 * 
 * 测试整个 4MB PSRAM 空间的读写
 * 设计为从 SRAM 运行，以便测试完整的 PSRAM 空间
 * 使用 -Os 优化以减小代码体积
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define PSRAM_BASE  0x80000000
#define PSRAM_SIZE  (4 * 1024 * 1024)  // 4MB
#define WORD_COUNT  (PSRAM_SIZE / 4)

// 测试进度显示间隔（每 256KB 显示一次）
#define PROGRESS_INTERVAL (256 * 1024 / 4)

// 直接 UART 输出（避免使用 printf 的大缓冲区）
#define UART_BASE   0x10000000
static inline void uart_putc(char c) {
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    while ((uart[5*4] & 0x20) == 0);  // 等待 THR 空 (LSR offset = 5*4)
    *uart = c;
}

static void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

static void uart_hex(uint32_t val) {
    const char *hex = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(val >> i) & 0xf]);
}

static void uart_dec(uint32_t val) {
    if (val == 0) { uart_putc('0'); return; }
    char buf[12];
    int i = 0;
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }
    while (i > 0) uart_putc(buf[--i]);
}

static int errors = 0;

// 测试1: 地址作为数据
static int test_address_data(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int pass = 1;
    
    uart_puts("\n[Test 1] Address as data pattern\n");
    
    // 写入阶段
    uart_puts("  Writing: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        psram[i] = PSRAM_BASE + i * 4;
        if (i % PROGRESS_INTERVAL == 0) uart_putc('W');
    }
    uart_puts(" done\n");
    
    // 读取验证阶段
    uart_puts("  Reading: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        uint32_t expected = PSRAM_BASE + i * 4;
        uint32_t actual = psram[i];
        if (actual != expected) {
            if (errors < 5) {
                uart_puts("\n  ERR@");
                uart_hex(PSRAM_BASE + i * 4);
                uart_puts(": exp=");
                uart_hex(expected);
                uart_puts(" got=");
                uart_hex(actual);
            }
            errors++;
            pass = 0;
        }
        if (i % PROGRESS_INTERVAL == 0) uart_putc('R');
    }
    uart_puts(pass ? " PASS\n" : " FAIL\n");
    
    return pass;
}

// 测试2: 反转模式
static int test_inverted(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int pass = 1;
    
    uart_puts("\n[Test 2] Inverted pattern\n");
    
    // 写入反转数据
    uart_puts("  Writing: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        psram[i] = ~(PSRAM_BASE + i * 4);
        if (i % PROGRESS_INTERVAL == 0) uart_putc('W');
    }
    uart_puts(" done\n");
    
    // 读取验证
    uart_puts("  Reading: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        uint32_t expected = ~(PSRAM_BASE + i * 4);
        uint32_t actual = psram[i];
        if (actual != expected) {
            if (errors < 5) {
                uart_puts("\n  ERR@");
                uart_hex(PSRAM_BASE + i * 4);
                uart_puts(": exp=");
                uart_hex(expected);
                uart_puts(" got=");
                uart_hex(actual);
            }
            errors++;
            pass = 0;
        }
        if (i % PROGRESS_INTERVAL == 0) uart_putc('R');
    }
    uart_puts(pass ? " PASS\n" : " FAIL\n");
    
    return pass;
}

// 测试3: 固定模式
static int test_fixed_patterns(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int pass = 1;
    uint32_t patterns[] = {0x55555555, 0xAAAAAAAA, 0x00000000, 0xFFFFFFFF};
    
    uart_puts("\n[Test 3] Fixed patterns\n");
    
    for (int p = 0; p < 4; p++) {
        uint32_t pattern = patterns[p];
        uart_puts("  Pattern ");
        uart_hex(pattern);
        uart_puts(": ");
        
        // 写入
        for (uint32_t i = 0; i < WORD_COUNT; i++) {
            psram[i] = pattern;
        }
        uart_puts("W ");
        
        // 读取验证
        int ppass = 1;
        for (uint32_t i = 0; i < WORD_COUNT; i++) {
            uint32_t actual = psram[i];
            if (actual != pattern) {
                if (errors < 5) {
                    uart_puts("\n  ERR@");
                    uart_hex(PSRAM_BASE + i * 4);
                    uart_puts(": got=");
                    uart_hex(actual);
                }
                errors++;
                ppass = 0;
                pass = 0;
            }
        }
        uart_puts(ppass ? "R PASS\n" : "R FAIL\n");
    }
    
    return pass;
}

int main(const char *args) {
    uart_puts("\n");
    uart_puts("========================================\n");
    uart_puts("    PSRAM 4MB Complete Memory Test\n");
    uart_puts("      (Running from SRAM)\n");
    uart_puts("========================================\n");
    uart_puts("PSRAM Base: ");
    uart_hex(PSRAM_BASE);
    uart_puts("\nPSRAM Size: ");
    uart_dec(PSRAM_SIZE / (1024*1024));
    uart_puts(" MB (");
    uart_dec(WORD_COUNT);
    uart_puts(" words)\n");
    
    int pass = 1;
    
    pass &= test_address_data();
    pass &= test_inverted();
    pass &= test_fixed_patterns();
    
    uart_puts("\n========================================\n");
    if (errors > 0) {
        uart_puts("FAILED: ");
        uart_dec(errors);
        uart_puts(" errors found\n");
    } else {
        uart_puts("PASSED: All tests completed successfully!\n");
    }
    uart_puts("========================================\n");
    
    return pass ? 0 : 1;
}
