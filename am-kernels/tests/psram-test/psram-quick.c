/* PSRAM 快速测试
 * 
 * 快速验证 PSRAM 功能
 * 预期在 1 分钟内完成
 * 
 * 注意：PSRAM 开头被 BSS 段占用（包括 printf 的 4KB 缓冲区）
 * 安全测试区域从 0x80010000 (64KB) 开始
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define PSRAM_BASE  0x80000000
#define PSRAM_SIZE  (4 * 1024 * 1024)  // 4MB

// 安全测试区域：跳过 BSS 段（64KB 应该足够保险）
#define SAFE_TEST_BASE  (PSRAM_BASE + 0x10000)
#define SAFE_TEST_SIZE  (PSRAM_SIZE - 0x10000)

// 快速测试参数
#define QUICK_TEST_SIZE  (4 * 1024)    // 完整测试 4KB
#define SAMPLE_STRIDE    (64 * 1024)   // 抽样间隔 64KB

static int errors = 0;

// 打印十六进制
static void print_hex(uint32_t val) {
    char buf[9];
    const char *hex = "0123456789abcdef";
    for (int i = 7; i >= 0; i--) {
        buf[i] = hex[val & 0xf];
        val >>= 4;
    }
    buf[8] = '\0';
    printf("0x%s", buf);
}

// 测试1: 完整测试小区域
static int test_region(uint32_t base, uint32_t size) {
    volatile uint32_t *mem = (volatile uint32_t *)base;
    uint32_t word_count = size / 4;
    int pass = 1;
    
    printf("  Testing ");
    print_hex(base);
    printf(" - ");
    print_hex(base + size);
    printf(" (%d KB)\n", size / 1024);
    
    // 写入地址作为数据
    printf("    Write addr pattern... ");
    for (uint32_t i = 0; i < word_count; i++) {
        mem[i] = base + i * 4;
    }
    printf("done\n");
    
    // 读取验证
    printf("    Read verify... ");
    for (uint32_t i = 0; i < word_count; i++) {
        uint32_t expected = base + i * 4;
        uint32_t actual = mem[i];
        if (actual != expected) {
            if (errors < 3) {
                printf("\n    ERR@");
                print_hex(base + i * 4);
                printf(": exp=");
                print_hex(expected);
                printf(" got=");
                print_hex(actual);
            }
            errors++;
            pass = 0;
        }
    }
    printf(" %s\n", pass ? "PASS" : "FAIL");
    
    // 写入反转模式
    printf("    Write inverted... ");
    for (uint32_t i = 0; i < word_count; i++) {
        mem[i] = ~(base + i * 4);
    }
    printf("done\n");
    
    // 读取验证
    printf("    Read verify... ");
    int pass2 = 1;
    for (uint32_t i = 0; i < word_count; i++) {
        uint32_t expected = ~(base + i * 4);
        uint32_t actual = mem[i];
        if (actual != expected) {
            if (errors < 3) {
                printf("\n    ERR@");
                print_hex(base + i * 4);
                printf(": exp=");
                print_hex(expected);
                printf(" got=");
                print_hex(actual);
            }
            errors++;
            pass2 = 0;
        }
    }
    printf(" %s\n", pass2 ? "PASS" : "FAIL");
    
    return pass && pass2;
}

// 测试2: 抽样测试整个可用空间
static int test_sampling(void) {
    int pass = 1;
    int samples = 0;
    int sample_errors = 0;
    
    printf("\n[Test 2] Sampling test (every %d KB)\n", SAMPLE_STRIDE / 1024);
    printf("  Range: ");
    print_hex(SAFE_TEST_BASE);
    printf(" - ");
    print_hex(SAFE_TEST_BASE + SAFE_TEST_SIZE);
    printf("\n");
    
    // 写入阶段 - 每隔 SAMPLE_STRIDE 写入一个测试值
    printf("  Writing samples... ");
    for (uint32_t addr = SAFE_TEST_BASE; addr < SAFE_TEST_BASE + SAFE_TEST_SIZE; addr += SAMPLE_STRIDE) {
        volatile uint32_t *ptr = (volatile uint32_t *)addr;
        *ptr = addr;
        samples++;
    }
    printf("%d samples written\n", samples);
    
    // 读取验证阶段
    printf("  Reading samples... ");
    for (uint32_t addr = SAFE_TEST_BASE; addr < SAFE_TEST_BASE + SAFE_TEST_SIZE; addr += SAMPLE_STRIDE) {
        volatile uint32_t *ptr = (volatile uint32_t *)addr;
        uint32_t expected = addr;
        uint32_t actual = *ptr;
        if (actual != expected) {
            if (sample_errors < 3) {
                printf("\n  ERR@");
                print_hex(addr);
                printf(": exp=");
                print_hex(expected);
                printf(" got=");
                print_hex(actual);
            }
            sample_errors++;
            errors++;
            pass = 0;
        }
    }
    printf(" %s (%d/%d passed)\n", pass ? "PASS" : "FAIL", samples - sample_errors, samples);
    
    // 测试边界地址（避开 BSS）
    printf("  Testing boundary addresses...\n");
    volatile uint32_t *ptr;
    uint32_t test_addrs[] = {
        SAFE_TEST_BASE,                      // 安全起始地址
        PSRAM_BASE + PSRAM_SIZE - 4,         // 结束地址
        PSRAM_BASE + 0x100000,               // 1MB
        PSRAM_BASE + 0x200000,               // 2MB
        PSRAM_BASE + 0x300000,               // 3MB
    };
    
    for (int i = 0; i < 5; i++) {
        uint32_t addr = test_addrs[i];
        ptr = (volatile uint32_t *)addr;
        uint32_t pattern = 0xDEADBEEF;
        *ptr = pattern;
        uint32_t read = *ptr;
        if (read != pattern) {
            printf("    FAIL@");
            print_hex(addr);
            printf(": wrote ");
            print_hex(pattern);
            printf(" read ");
            print_hex(read);
            printf("\n");
            pass = 0;
            errors++;
        } else {
            printf("    ");
            print_hex(addr);
            printf(": OK\n");
        }
    }
    
    return pass;
}

// 测试3: 字节访问测试（使用安全区域）
static int test_byte_access(void) {
    volatile uint8_t *mem = (volatile uint8_t *)SAFE_TEST_BASE;
    int pass = 1;
    
    printf("\n[Test 3] Byte access test (16 bytes at ");
    print_hex(SAFE_TEST_BASE);
    printf(")\n");
    
    // 写入字节模式
    printf("  Writing bytes 0x00-0x0F... ");
    for (int i = 0; i < 16; i++) {
        mem[i] = i;
    }
    printf("done\n");
    
    // 读取验证
    printf("  Reading bytes... ");
    for (int i = 0; i < 16; i++) {
        uint8_t actual = mem[i];
        if (actual != i) {
            printf("FAIL at byte %d\n", i);
            pass = 0;
            errors++;
        }
    }
    if (pass) printf("PASS\n");
    
    // 测试半字访问（使用安全区域）
    printf("  Testing halfword access... ");
    volatile uint16_t *mem16 = (volatile uint16_t *)(SAFE_TEST_BASE + 0x100);
    mem16[0] = 0x1234;
    mem16[1] = 0x5678;
    uint16_t h0 = mem16[0];
    uint16_t h1 = mem16[1];
    if (h0 != 0x1234 || h1 != 0x5678) {
        printf("FAIL\n");
        pass = 0;
        errors++;
    } else {
        printf("PASS\n");
    }
    
    return pass;
}

int main(const char *args) {
    printf("\n");
    printf("======================================\n");
    printf("      PSRAM Quick Memory Test\n");
    printf("======================================\n");
    printf("PSRAM Base: ");
    print_hex(PSRAM_BASE);
    printf("\n");
    printf("PSRAM Size: %d MB\n", PSRAM_SIZE / (1024*1024));
    printf("Safe test area: ");
    print_hex(SAFE_TEST_BASE);
    printf(" - ");
    print_hex(SAFE_TEST_BASE + SAFE_TEST_SIZE);
    printf("\n");
    
    int pass = 1;
    
    // 测试1: 完整测试安全区域开头
    printf("\n[Test 1] Full test of %d KB at ", QUICK_TEST_SIZE / 1024);
    print_hex(SAFE_TEST_BASE);
    printf("\n");
    pass &= test_region(SAFE_TEST_BASE, QUICK_TEST_SIZE);
    pass &= test_sampling();
    
    // 测试字节访问
    pass &= test_byte_access();
    
    printf("\n======================================\n");
    if (errors > 0) {
        printf("FAILED: %d errors found\n", errors);
        pass = 0;
    } else {
        printf("PASSED: All quick tests completed!\n");
    }
    printf("======================================\n");
    
    return pass ? 0 : 1;
}
