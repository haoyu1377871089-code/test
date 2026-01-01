/* 直接测试 SRAM 写入能力（从 Flash 运行） */
#include <am.h>
#include <klib.h>

#define SRAM_BASE 0x0f000000
#define UART_BASE 0x10000000

// 直接 UART 输出
static void put_hex(uint32_t val) {
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    const char hex[] = "0123456789abcdef";
    for (int i = 28; i >= 0; i -= 4) {
        while (!(uart[5*4] & 0x20));  // wait THRE
        uart[0] = hex[(val >> i) & 0xf];
    }
}

static void put_str(const char *s) {
    volatile uint8_t *uart = (volatile uint8_t *)UART_BASE;
    while (*s) {
        while (!(uart[5*4] & 0x20));
        uart[0] = *s++;
    }
}

int main(const char *args) {
    put_str("\n=== SRAM Write Test (from Flash) ===\n");
    
    volatile uint32_t *sram = (volatile uint32_t *)SRAM_BASE;
    
    // 测试 SRAM 不同位置
    put_str("Writing 0xDEADBEEF to SRAM[256]...\n");
    sram[256] = 0xDEADBEEF;  // 避开可能的代码区
    
    put_str("Reading back: 0x");
    uint32_t val = sram[256];
    put_hex(val);
    put_str("\n");
    
    if (val == 0xDEADBEEF) {
        put_str("SRAM write/read test PASSED!\n");
        return 0;
    } else {
        put_str("SRAM write/read test FAILED! Expected 0xDEADBEEF, got 0x");
        put_hex(val);
        put_str("\n");
        return 1;
    }
}
