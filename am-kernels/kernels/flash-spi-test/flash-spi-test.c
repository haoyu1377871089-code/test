#include <am.h>
#include <klib-macros.h>

// 声明 AM 提供的 flash_read 函数
extern uint32_t flash_read(uint32_t addr);

// 与仿真环境中 memory.cpp 定义的测试模式保持一致
// 测试数据位于 Flash 偏移 0x00100000 处
#define FLASH_TEST_OFFSET 0x00100000
#define FLASH_TEST_PATTERN_COUNT 16

static uint32_t expected_patterns[FLASH_TEST_PATTERN_COUNT] = {
    0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00,
    0x11111111, 0x22222222, 0x33333333, 0x44444444,
    0x55555555, 0x66666666, 0x77777777, 0x88888888,
    0x99999999, 0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC
};

// 打印十六进制数
void print_hex(uint32_t val) {
    const char hex[] = "0123456789ABCDEF";
    putstr("0x");
    for (int i = 7; i >= 0; i--) {
        putch(hex[(val >> (i * 4)) & 0xF]);
    }
}

int main(const char *args) {
    putstr("=== Flash SPI Read Test ===\n");
    putstr("Using AM flash_read() from spi.c\n\n");

    int pass_count = 0;
    int fail_count = 0;

    for (int i = 0; i < FLASH_TEST_PATTERN_COUNT; i++) {
        uint32_t addr = FLASH_TEST_OFFSET + i * 4;
        uint32_t expected = expected_patterns[i];
        uint32_t result = flash_read(addr);

        if (result == expected) {
            putstr("[PASS] ");
            pass_count++;
        } else {
            putstr("[FAIL] ");
            fail_count++;
        }
        
        putstr("Addr=");
        print_hex(addr);
        putstr(" Read=");
        print_hex(result);
        putstr(" Exp=");
        print_hex(expected);
        putstr("\n");
    }

    putstr("\n=== Summary ===\n");
    if (fail_count == 0) {
        putstr("*** ALL TESTS PASSED! ***\n");
        return 0;
    } else {
        putstr("*** SOME TESTS FAILED! ***\n");
        halt(1);
        return 1;
    }
}
