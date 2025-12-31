// PSRAM 完整测试程序
// 测试多个地址的读写

typedef unsigned int uint32_t;
typedef unsigned char uint8_t;

#define PSRAM_BASE 0x80000000

// 直接写入UART进行输出
#define UART_BASE 0x10000000
static inline void uart_putc(char c) {
    while (!(*(volatile uint8_t*)(UART_BASE + 5) & 0x20)); // wait for THR empty
    *(volatile uint8_t*)UART_BASE = c;
}

static void print_str(const char* s) {
    while (*s) uart_putc(*s++);
}

static void print_hex(uint32_t val) {
    const char* hex = "0123456789abcdef";
    uart_putc('0'); uart_putc('x');
    for (int i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xf]);
    }
}

// 测试用例
static uint32_t test_patterns[] = {
    0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00,
    0x00000000, 0xFFFFFFFF, 0x55555555, 0xAAAAAAAA
};

void _start() {
    volatile uint32_t* psram = (volatile uint32_t*)PSRAM_BASE;
    int pass = 1;
    int num_patterns = 8;
    
    print_str("PSRAM Test Start\n");
    
    // 写入测试数据
    print_str("Writing patterns...\n");
    for (int i = 0; i < num_patterns; i++) {
        psram[i] = test_patterns[i];
    }
    
    // 读回验证
    print_str("Verifying...\n");
    for (int i = 0; i < num_patterns; i++) {
        uint32_t val = psram[i];
        if (val != test_patterns[i]) {
            print_str("FAIL at offset ");
            print_hex(i * 4);
            print_str(": expected ");
            print_hex(test_patterns[i]);
            print_str(", got ");
            print_hex(val);
            print_str("\n");
            pass = 0;
        }
    }
    
    if (pass) {
        print_str("PSRAM Test PASSED!\n");
        // GOOD TRAP - 使用标准ebreak
        asm volatile("li a0, 0; ebreak");
    } else {
        print_str("PSRAM Test FAILED!\n");
        // BAD TRAP
        asm volatile("li a0, 1; ebreak");
    }
    
    while(1);
}
