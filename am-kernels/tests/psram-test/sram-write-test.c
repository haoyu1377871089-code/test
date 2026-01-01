/* 测试 SRAM 写入（在 Flash 上运行） */
#include <am.h>
#include <klib.h>

int main(const char *args) {
    printf("Testing SRAM write from Flash...\n");
    
    volatile uint32_t *sram = (volatile uint32_t *)0x0f000000;
    
    printf("Writing to SRAM[0]...\n");
    sram[0] = 0xDEADBEEF;
    printf("Write done.\n");
    
    printf("Reading from SRAM[0]...\n");
    uint32_t v = sram[0];
    printf("SRAM[0] = 0x%08x\n", v);
    
    if (v == 0xDEADBEEF) {
        printf("SRAM test PASSED!\n");
        return 0;
    } else {
        printf("SRAM test FAILED!\n");
        return 1;
    }
}
