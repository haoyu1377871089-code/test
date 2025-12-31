// PSRAM 多地址测试程序（无打印）

typedef unsigned int uint32_t;

#define PSRAM_BASE 0x80000000

// 测试用例
static uint32_t test_patterns[] = {
    0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00,
    0x00000000, 0xFFFFFFFF, 0x55555555, 0xAAAAAAAA
};

void _start() {
    volatile uint32_t* psram = (volatile uint32_t*)PSRAM_BASE;
    int num_patterns = 8;
    
    // 写入测试数据
    for (int i = 0; i < num_patterns; i++) {
        psram[i] = test_patterns[i];
    }
    
    // 读回验证
    for (int i = 0; i < num_patterns; i++) {
        uint32_t val = psram[i];
        if (val != test_patterns[i]) {
            // BAD TRAP
            asm volatile("li a0, 1; ebreak");
            while(1);
        }
    }
    
    // 全部通过 - GOOD TRAP
    asm volatile("li a0, 0; ebreak");
    while(1);
}
