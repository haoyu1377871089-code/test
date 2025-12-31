// 简单 PSRAM 测试程序
#include <am.h>
#include <klib.h>

#define PSRAM_BASE 0x80000000UL

// 简单输出字符串
static void puts_simple(const char *s) {
    while (*s) putch(*s++);
}

// 输出十六进制
static void print_hex(uint32_t val) {
    puts_simple("0x");
    for (int i = 28; i >= 0; i -= 4) {
        int d = (val >> i) & 0xF;
        putch(d < 10 ? '0' + d : 'a' + d - 10);
    }
}

int main(void) {
    puts_simple("Simple PSRAM Test\n");
    
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    
    puts_simple("Writing 0xDEADBEEF to PSRAM[0]...\n");
    psram[0] = 0xDEADBEEF;
    
    puts_simple("Reading PSRAM[0]: ");
    uint32_t val = psram[0];
    print_hex(val);
    putch('\n');
    
    if (val == 0xDEADBEEF) {
        puts_simple("PASS!\n");
        return 0;
    } else {
        puts_simple("FAIL!\n");
        return 1;
    }
}
