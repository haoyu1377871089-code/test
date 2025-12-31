// PSRAM 大范围地址测试程序

typedef unsigned int uint32_t;

#define PSRAM_BASE 0x80000000
#define TEST_SIZE  256  // 测试256个words = 1KB

void _start() {
    volatile uint32_t* psram = (volatile uint32_t*)PSRAM_BASE;
    
    // 写入测试数据：地址作为数据
    for (uint32_t i = 0; i < TEST_SIZE; i++) {
        psram[i] = 0x12340000 | i;
    }
    
    // 读回验证
    for (uint32_t i = 0; i < TEST_SIZE; i++) {
        uint32_t expected = 0x12340000 | i;
        uint32_t val = psram[i];
        if (val != expected) {
            // BAD TRAP
            asm volatile("li a0, 1; ebreak");
            while(1);
        }
    }
    
    // 全部通过 - GOOD TRAP
    asm volatile("li a0, 0; ebreak");
    while(1);
}
