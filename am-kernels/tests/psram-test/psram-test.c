// PSRAM 测试程序
// 测试 IS66WVS4M8ALL PSRAM 颗粒 (4MB, 映射到 0x80000000)

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define PSRAM_BASE 0x80000000UL
#define TEST_SIZE  (4 * 1024)  // 测试 4KB

// 测试模式
#define PATTERN1 0xDEADBEEF
#define PATTERN2 0x12345678
#define PATTERN3 0xA5A5A5A5

static void print_progress(const char *msg, int current, int total) {
    printf("%s: %d/%d\n", msg, current, total);
}

// 字节读写测试
static int test_byte_rw(void) {
    volatile uint8_t *psram = (volatile uint8_t *)PSRAM_BASE;
    printf("[Test 1] Byte read/write test (256 bytes)\n");
    
    // 写入
    for (int i = 0; i < 256; i++) {
        psram[i] = (uint8_t)i;
    }
    printf("  Write done\n");
    
    // 读回验证
    for (int i = 0; i < 256; i++) {
        uint8_t val = psram[i];
        if (val != (uint8_t)i) {
            printf("  FAIL at offset %d: expected 0x%02x, got 0x%02x\n", i, (uint8_t)i, val);
            return 1;
        }
    }
    printf("  PASS\n");
    return 0;
}

// 半字读写测试
static int test_halfword_rw(void) {
    volatile uint16_t *psram = (volatile uint16_t *)PSRAM_BASE;
    printf("[Test 2] Halfword read/write test (256 halfwords)\n");
    
    // 写入
    for (int i = 0; i < 256; i++) {
        psram[i] = (uint16_t)(0xAB00 + i);
    }
    printf("  Write done\n");
    
    // 读回验证
    for (int i = 0; i < 256; i++) {
        uint16_t expected = (uint16_t)(0xAB00 + i);
        uint16_t val = psram[i];
        if (val != expected) {
            printf("  FAIL at offset %d: expected 0x%04x, got 0x%04x\n", i, expected, val);
            return 1;
        }
    }
    printf("  PASS\n");
    return 0;
}

// 字读写测试
static int test_word_rw(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int count = TEST_SIZE / 4;
    printf("[Test 3] Word read/write test (%d words)\n", count);
    
    // 写入递增模式
    for (int i = 0; i < count; i++) {
        psram[i] = PATTERN1 + i;
        if (i % 256 == 0) {
            print_progress("  Writing", i, count);
        }
    }
    printf("  Write done\n");
    
    // 读回验证
    for (int i = 0; i < count; i++) {
        uint32_t expected = PATTERN1 + i;
        uint32_t val = psram[i];
        if (val != expected) {
            printf("  FAIL at offset %d: expected 0x%08x, got 0x%08x\n", i, expected, val);
            return 1;
        }
        if (i % 256 == 0) {
            print_progress("  Verifying", i, count);
        }
    }
    printf("  PASS\n");
    return 0;
}

// 棋盘模式测试
static int test_checkerboard(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int count = 512;  // 2KB
    printf("[Test 4] Checkerboard pattern test\n");
    
    // 写入 0xAAAAAAAA 和 0x55555555 交替
    for (int i = 0; i < count; i++) {
        psram[i] = (i & 1) ? 0x55555555 : 0xAAAAAAAA;
    }
    printf("  Write done\n");
    
    // 读回验证
    for (int i = 0; i < count; i++) {
        uint32_t expected = (i & 1) ? 0x55555555 : 0xAAAAAAAA;
        uint32_t val = psram[i];
        if (val != expected) {
            printf("  FAIL at offset %d: expected 0x%08x, got 0x%08x\n", i, expected, val);
            return 1;
        }
    }
    printf("  PASS\n");
    return 0;
}

// 地址作为数据测试
static int test_address_as_data(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int count = 256;
    printf("[Test 5] Address as data test\n");
    
    // 写入地址值
    for (int i = 0; i < count; i++) {
        psram[i] = (uint32_t)&psram[i];
    }
    printf("  Write done\n");
    
    // 读回验证
    for (int i = 0; i < count; i++) {
        uint32_t expected = (uint32_t)&psram[i];
        uint32_t val = psram[i];
        if (val != expected) {
            printf("  FAIL at offset %d: expected 0x%08x, got 0x%08x\n", i, expected, val);
            return 1;
        }
    }
    printf("  PASS\n");
    return 0;
}

int main(void) {
    printf("========================================\n");
    printf("  PSRAM Memory Test (IS66WVS4M8ALL)\n");
    printf("  Base: 0x%08x, Size: %d bytes\n", PSRAM_BASE, TEST_SIZE);
    printf("========================================\n");
    
    int failures = 0;
    
    failures += test_byte_rw();
    failures += test_halfword_rw();
    failures += test_word_rw();
    failures += test_checkerboard();
    failures += test_address_as_data();
    
    printf("========================================\n");
    if (failures == 0) {
        printf("All tests PASSED!\n");
    } else {
        printf("%d test(s) FAILED!\n", failures);
    }
    printf("========================================\n");
    
    return failures;
}
