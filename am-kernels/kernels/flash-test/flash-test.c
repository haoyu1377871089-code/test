#include <am.h>
#include <klib-macros.h>

// Flash 测试 - 验证从 Flash 读取的数据与仿真环境初始化时写入的数据一致
// Flash 地址空间: 0x30000000 ~ 0x3fffffff
// 测试数据位于 Flash 偏移 0x00100000 处 (绝对地址 0x30100000)

#define FLASH_BASE        0x30000000
#define FLASH_TEST_OFFSET 0x00100000
#define FLASH_TEST_ADDR   (FLASH_BASE + FLASH_TEST_OFFSET)
#define FLASH_TEST_PATTERN_COUNT 16

// 与仿真环境中 memory.cpp 定义的测试模式保持一致
static uint32_t expected_patterns[FLASH_TEST_PATTERN_COUNT] = {
    0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xABCDEF00,
    0x11111111, 0x22222222, 0x33333333, 0x44444444,
    0x55555555, 0x66666666, 0x77777777, 0x88888888,
    0x99999999, 0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC
};

int main(const char *args) {
    putstr("=== Flash Read Test ===\n");

    int pass_count = 0;
    int fail_count = 0;

    for (int i = 0; i < FLASH_TEST_PATTERN_COUNT; i++) {
        volatile uint32_t *addr = (volatile uint32_t *)(FLASH_TEST_ADDR + i * 4);
        uint32_t read_value = *addr;
        uint32_t expected = expected_patterns[i];

        if (read_value == expected) {
            putstr("[PASS] Pattern ");
            putch('0' + i);
            putstr("\n");
            pass_count++;
        } else {
            putstr("[FAIL] Pattern ");
            putch('0' + i);
            putstr("\n");
            fail_count++;
        }
    }

    putstr("\n=== Test Summary ===\n");
    if (fail_count == 0) {
        putstr("*** ALL FLASH TESTS PASSED! ***\n");
        return 0;
    } else {
        putstr("*** FLASH TESTS FAILED! ***\n");
        halt(1);
        return 1;
    }
}
