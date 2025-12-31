// PSRAM 写测试程序
// 简单测试写操作

typedef unsigned int uint32_t;

#define PSRAM_BASE 0x80000000

void _start() {
    volatile uint32_t* psram = (volatile uint32_t*)PSRAM_BASE;
    
    // 写入一个值
    psram[0] = 0x12345678;
    
    // 读回验证
    uint32_t val = psram[0];
    
    if (val == 0x12345678) {
        asm volatile("mv a0, zero");  // pass
    } else {
        asm volatile("li a0, 1");     // fail
    }
    
    // 触发结束
    asm volatile("ebreak");
    
    while(1);
}
