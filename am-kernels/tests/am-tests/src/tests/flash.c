#include <amtest.h>

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

void flash_test() {
    printf("=== Flash Read Test ===\n");
    printf("Flash base address: 0x%08x\n", FLASH_BASE);
    printf("Test data address:  0x%08x\n", FLASH_TEST_ADDR);
    printf("Testing %d patterns...\n\n", FLASH_TEST_PATTERN_COUNT);

    int pass_count = 0;
    int fail_count = 0;

    for (int i = 0; i < FLASH_TEST_PATTERN_COUNT; i++) {
        volatile uint32_t *addr = (volatile uint32_t *)(FLASH_TEST_ADDR + i * 4);
        uint32_t read_value = *addr;
        uint32_t expected = expected_patterns[i];

        if (read_value == expected) {
            printf("[PASS] addr=0x%08x: read=0x%08x, expected=0x%08x\n",
                   (uint32_t)addr, read_value, expected);
            pass_count++;
        } else {
            printf("[FAIL] addr=0x%08x: read=0x%08x, expected=0x%08x\n",
                   (uint32_t)addr, read_value, expected);
            fail_count++;
        }
    }

    printf("\n=== Test Summary ===\n");
    printf("PASS: %d / %d\n", pass_count, FLASH_TEST_PATTERN_COUNT);
    printf("FAIL: %d / %d\n", fail_count, FLASH_TEST_PATTERN_COUNT);

    if (fail_count == 0) {
        printf("\n*** ALL FLASH TESTS PASSED! ***\n");
    } else {
        printf("\n*** FLASH TESTS FAILED! ***\n");
        halt(1);
    }
}
