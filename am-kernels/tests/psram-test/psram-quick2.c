/* PSRAM 简单快速测试
 * 
 * 立即写后读验证，避免缓存问题
 * 注意：PSRAM 开头被 BSS 段占用（包括 printf 的 4KB 缓冲区）
 * 安全测试区域从 0x80010000 开始
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define PSRAM_BASE  0x80000000
#define PSRAM_SIZE  (4 * 1024 * 1024)  // 4MB

// 安全测试区域：跳过 BSS 段（约 64KB 应该足够保险）
#define SAFE_TEST_BASE  (PSRAM_BASE + 0x10000)
#define SAFE_TEST_SIZE  (PSRAM_SIZE - 0x10000)

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

// 测试1: 立即写后读（避免缓存问题）
static int test_immediate_verify(void) {
    int pass = 1;
    
    printf("\n[Test 1] Immediate write-read verify (64 locations)\n");
    printf("  Test range: ");
    print_hex(SAFE_TEST_BASE);
    printf(" - ");
    print_hex(SAFE_TEST_BASE + SAFE_TEST_SIZE);
    printf("\n");
    
    // 在安全测试区域内均匀选择64个位置
    for (int i = 0; i < 64; i++) {
        uint32_t addr = SAFE_TEST_BASE + i * (SAFE_TEST_SIZE / 64);
        volatile uint32_t *ptr = (volatile uint32_t *)addr;
        
        // 测试模式1：地址作为数据
        *ptr = addr;
        uint32_t read1 = *ptr;
        if (read1 != addr) {
            if (errors < 5) {
                printf("  FAIL@");
                print_hex(addr);
                printf(": wrote ");
                print_hex(addr);
                printf(" read ");
                print_hex(read1);
                printf("\n");
            }
            errors++;
            pass = 0;
        }
        
        // 测试模式2：反转模式
        *ptr = ~addr;
        uint32_t read2 = *ptr;
        if (read2 != ~addr) {
            if (errors < 5) {
                printf("  FAIL@");
                print_hex(addr);
                printf(": wrote ~addr read ");
                print_hex(read2);
                printf("\n");
            }
            errors++;
            pass = 0;
        }
        
        // 每16个显示进度
        if ((i + 1) % 16 == 0) {
            printf("  Progress: %d/64\n", i + 1);
        }
    }
    
    printf("  Result: %s\n", pass ? "PASS" : "FAIL");
    return pass;
}

// 测试2: 连续写入测试 - 找出问题的边界
static int test_batch_small(void) {
    // 使用安全区域，远离 BSS
    volatile uint32_t *mem = (volatile uint32_t *)(SAFE_TEST_BASE + 0x100000); // 1MB偏移
    int pass = 1;
    
    printf("\n[Test 2] Consecutive writes test at ");
    print_hex((uint32_t)mem);
    printf("\n");
    
    // 测试连续写入2个字
    printf("  Test: write 2 words, verify both\n");
    mem[0] = 0xAAAA0000;
    mem[1] = 0xBBBB0001;
    uint32_t r0 = mem[0];
    uint32_t r1 = mem[1];
    printf("    [0]: wrote 0xaaaa0000, read ");
    print_hex(r0);
    printf(" %s\n", r0 == 0xAAAA0000 ? "OK" : "FAIL");
    printf("    [1]: wrote 0xbbbb0001, read ");
    print_hex(r1);
    printf(" %s\n", r1 == 0xBBBB0001 ? "OK" : "FAIL");
    if (r0 != 0xAAAA0000 || r1 != 0xBBBB0001) {
        errors++;
        pass = 0;
    }
    
    // 测试连续写入4个字
    printf("  Test: write 4 words, verify all\n");
    mem[0] = 0x11110000;
    mem[1] = 0x22220001;
    mem[2] = 0x33330002;
    mem[3] = 0x44440003;
    for (int i = 0; i < 4; i++) {
        uint32_t expected = 0x11110000 + i * 0x11110001;
        uint32_t actual = mem[i];
        printf("    [%d]: ", i);
        print_hex(actual);
        if (actual != expected) {
            printf(" FAIL (exp ");
            print_hex(expected);
            printf(")\n");
            errors++;
            pass = 0;
        } else {
            printf(" OK\n");
        }
    }
    
    // 测试：写入后加入printf再读
    printf("  Test: write with printf between\n");
    mem[0] = 0xDEAD0000;
    printf("    Wrote [0]=0xdead0000\n");
    mem[1] = 0xBEEF0001;
    printf("    Wrote [1]=0xbeef0001\n");
    r0 = mem[0];
    r1 = mem[1];
    printf("    Read [0]=");
    print_hex(r0);
    printf(" %s\n", r0 == 0xDEAD0000 ? "OK" : "FAIL");
    printf("    Read [1]=");
    print_hex(r1);
    printf(" %s\n", r1 == 0xBEEF0001 ? "OK" : "FAIL");
    if (r0 != 0xDEAD0000 || r1 != 0xBEEF0001) {
        errors++;
        pass = 0;
    }
    
    printf("  Result: %s\n", pass ? "PASS" : "FAIL");
    return pass;
}

// 测试3: 边界地址测试（避开 BSS 区域）
static int test_boundaries(void) {
    int pass = 1;
    
    printf("\n[Test 3] Boundary addresses (avoiding BSS)\n");
    
    uint32_t addrs[] = {
        SAFE_TEST_BASE,               // 安全起始
        PSRAM_BASE + PSRAM_SIZE - 4,  // 结束
        PSRAM_BASE + 0x100000,        // 1MB
        PSRAM_BASE + 0x200000,        // 2MB  
        PSRAM_BASE + 0x300000,        // 3MB
        PSRAM_BASE + 0x3F0000,        // 接近结束
    };
    
    for (int i = 0; i < 6; i++) {
        volatile uint32_t *ptr = (volatile uint32_t *)addrs[i];
        uint32_t pattern = 0xDEADBEEF;
        *ptr = pattern;
        uint32_t read = *ptr;
        printf("  ");
        print_hex(addrs[i]);
        if (read != pattern) {
            printf(": FAIL (got ");
            print_hex(read);
            printf(")\n");
            errors++;
            pass = 0;
        } else {
            printf(": PASS\n");
        }
    }
    
    return pass;
}

// 测试4: 字节访问（RMW）- 使用安全区域
static int test_byte_rmw(void) {
    volatile uint32_t *word = (volatile uint32_t *)(SAFE_TEST_BASE + 0x200000);
    volatile uint8_t *bytes = (volatile uint8_t *)(SAFE_TEST_BASE + 0x200000);
    int pass = 1;
    
    printf("\n[Test 4] Byte RMW test at ");
    print_hex((uint32_t)word);
    printf("\n");
    
    // 先写入一个完整字
    *word = 0x12345678;
    printf("  Write word 0x12345678: ");
    uint32_t r1 = *word;
    if (r1 != 0x12345678) {
        printf("FAIL (got ");
        print_hex(r1);
        printf(")\n");
        pass = 0;
        errors++;
    } else {
        printf("OK\n");
    }
    
    // 逐字节修改
    printf("  Modify byte[0] to 0xAA: ");
    bytes[0] = 0xAA;
    uint32_t r2 = *word;
    // 小端序：byte[0]是最低字节，期望 0x123456AA
    if (r2 != 0x123456AA) {
        printf("FAIL (got ");
        print_hex(r2);
        printf(")\n");
        pass = 0;
        errors++;
    } else {
        printf("OK (");
        print_hex(r2);
        printf(")\n");
    }
    
    printf("  Modify byte[3] to 0xBB: ");
    bytes[3] = 0xBB;
    uint32_t r3 = *word;
    // 期望 0xBB3456AA
    if (r3 != 0xBB3456AA) {
        printf("FAIL (got ");
        print_hex(r3);
        printf(")\n");
        pass = 0;
        errors++;
    } else {
        printf("OK (");
        print_hex(r3);
        printf(")\n");
    }
    
    return pass;
}

int main(const char *args) {
    printf("\n");
    printf("======================================\n");
    printf("      PSRAM Quick Test v2\n");
    printf("======================================\n");
    
    int pass = 1;
    
    pass &= test_immediate_verify();
    pass &= test_batch_small();
    pass &= test_boundaries();
    pass &= test_byte_rmw();
    
    printf("\n======================================\n");
    if (errors > 0) {
        printf("FAILED: %d errors found\n", errors);
    } else {
        printf("PASSED: All tests completed!\n");
    }
    printf("======================================\n");
    
    return errors > 0 ? 1 : 0;
}
