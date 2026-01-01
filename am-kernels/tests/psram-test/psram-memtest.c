/* PSRAM 4MB 完整测试
 * 
 * 测试整个 4MB PSRAM 空间的读写
 * 使用多种测试模式：
 * 1. 地址作为数据
 * 2. 反转模式
 * 3. Walking 1s/0s
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define PSRAM_BASE  0x80000000
#define PSRAM_SIZE  (4 * 1024 * 1024)  // 4MB
#define WORD_COUNT  (PSRAM_SIZE / 4)

// 测试进度显示间隔（每 256KB 显示一次）
#define PROGRESS_INTERVAL (256 * 1024 / 4)

static int errors = 0;

// 显示进度
static void show_progress(uint32_t current, uint32_t total, char phase) {
    static uint32_t last_percent = 0xFFFFFFFF;
    uint32_t percent = (current * 100) / total;
    if (percent != last_percent && (percent % 10 == 0)) {
        printf("%c%d%% ", phase, percent);
        last_percent = percent;
    }
}

// 测试1: 地址作为数据
static int test_address_data(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int pass = 1;
    
    printf("\n[Test 1] Address as data pattern\n");
    
    // 写入阶段
    printf("  Writing: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        psram[i] = PSRAM_BASE + i * 4;
        if (i % PROGRESS_INTERVAL == 0) show_progress(i, WORD_COUNT, 'W');
    }
    printf("W100%% done\n");
    
    // 读取验证阶段
    printf("  Reading: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        uint32_t expected = PSRAM_BASE + i * 4;
        uint32_t actual = psram[i];
        if (actual != expected) {
            if (errors < 10) {
                printf("\n  ERROR at 0x%08x: expected 0x%08x, got 0x%08x", 
                       PSRAM_BASE + i * 4, expected, actual);
            }
            errors++;
            pass = 0;
        }
        if (i % PROGRESS_INTERVAL == 0) show_progress(i, WORD_COUNT, 'R');
    }
    printf("R100%% done\n");
    
    return pass;
}

// 测试2: 反转模式
static int test_inverted(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int pass = 1;
    
    printf("\n[Test 2] Inverted pattern\n");
    
    // 写入反转数据
    printf("  Writing: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        psram[i] = ~(PSRAM_BASE + i * 4);
        if (i % PROGRESS_INTERVAL == 0) show_progress(i, WORD_COUNT, 'W');
    }
    printf("W100%% done\n");
    
    // 读取验证
    printf("  Reading: ");
    for (uint32_t i = 0; i < WORD_COUNT; i++) {
        uint32_t expected = ~(PSRAM_BASE + i * 4);
        uint32_t actual = psram[i];
        if (actual != expected) {
            if (errors < 10) {
                printf("\n  ERROR at 0x%08x: expected 0x%08x, got 0x%08x", 
                       PSRAM_BASE + i * 4, expected, actual);
            }
            errors++;
            pass = 0;
        }
        if (i % PROGRESS_INTERVAL == 0) show_progress(i, WORD_COUNT, 'R');
    }
    printf("R100%% done\n");
    
    return pass;
}

// 测试3: 固定模式 (0x55555555 和 0xAAAAAAAA)
static int test_fixed_patterns(void) {
    volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
    int pass = 1;
    uint32_t patterns[] = {0x55555555, 0xAAAAAAAA, 0x00000000, 0xFFFFFFFF};
    
    printf("\n[Test 3] Fixed patterns\n");
    
    for (int p = 0; p < 4; p++) {
        uint32_t pattern = patterns[p];
        printf("  Pattern 0x%08x: ", pattern);
        
        // 写入
        for (uint32_t i = 0; i < WORD_COUNT; i++) {
            psram[i] = pattern;
        }
        printf("W ");
        
        // 读取验证
        for (uint32_t i = 0; i < WORD_COUNT; i++) {
            uint32_t actual = psram[i];
            if (actual != pattern) {
                if (errors < 10) {
                    printf("\n  ERROR at 0x%08x: expected 0x%08x, got 0x%08x", 
                           PSRAM_BASE + i * 4, pattern, actual);
                }
                errors++;
                pass = 0;
            }
        }
        printf("R %s\n", pass ? "OK" : "FAIL");
    }
    
    return pass;
}

int main(const char *args) {
    printf("\n");
    printf("========================================\n");
    printf("    PSRAM 4MB Complete Memory Test\n");
    printf("========================================\n");
    printf("PSRAM Base: 0x%08x\n", PSRAM_BASE);
    printf("PSRAM Size: %d MB (%d bytes)\n", PSRAM_SIZE / (1024*1024), PSRAM_SIZE);
    printf("Test words: %d\n", WORD_COUNT);
    
    int pass = 1;
    
    pass &= test_address_data();
    pass &= test_inverted();
    pass &= test_fixed_patterns();
    
    printf("\n========================================\n");
    if (errors > 0) {
        printf("FAILED: %d errors found\n", errors);
    } else {
        printf("PASSED: All tests completed successfully!\n");
    }
    printf("========================================\n");
    
    return pass ? 0 : 1;
}
