// 最小 PSRAM 测试程序 - 无打印，直接在_start入口执行

typedef unsigned int uint32_t;

#define PSRAM_BASE 0x80000000UL

// 直接定义入口点
void _start() {
    // 设置栈指针（使用简单的内存地址）
    asm volatile("li sp, 0x0f002000");
    
    // 直接访问PSRAM
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    
    // 写入
    psram[0] = 0xDEADBEEF;
    
    // 读取
    uint32_t val = psram[0];
    
    // 检查结果
    if (val == 0xDEADBEEF) {
        asm volatile("li a0, 0; ebreak");  // GOOD TRAP - 标准ebreak
    } else {
        asm volatile("li a0, 1; ebreak");  // BAD TRAP - 标准ebreak  
    }
    
    // 永远不会到这里
    while(1);
}
