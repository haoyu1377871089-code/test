/* PSRAM 地址别名测试
 * 
 * 测试 PSRAM 是否存在地址别名问题
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define PSRAM_BASE  0x80000000

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

int main(const char *args) {
    printf("\n");
    printf("======================================\n");
    printf("      PSRAM Address Alias Test\n");
    printf("======================================\n");
    
    volatile uint32_t *p0 = (volatile uint32_t *)(PSRAM_BASE + 0x00000);
    volatile uint32_t *p1 = (volatile uint32_t *)(PSRAM_BASE + 0x10000);  // 64KB
    volatile uint32_t *p2 = (volatile uint32_t *)(PSRAM_BASE + 0x20000);  // 128KB
    volatile uint32_t *p3 = (volatile uint32_t *)(PSRAM_BASE + 0x100000); // 1MB
    volatile uint32_t *p4 = (volatile uint32_t *)(PSRAM_BASE + 0x200000); // 2MB
    
    printf("\n[Test] Write unique values to different addresses\n");
    
    // 写入唯一值
    *p0 = 0xAA000000;
    *p1 = 0xBB000001;
    *p2 = 0xCC000002;
    *p3 = 0xDD000003;
    *p4 = 0xEE000004;
    
    printf("  Written values:\n");
    printf("    p0 (0x80000000) = 0xaa000000\n");
    printf("    p1 (0x80010000) = 0xbb000001\n");
    printf("    p2 (0x80020000) = 0xcc000002\n");
    printf("    p3 (0x80100000) = 0xdd000003\n");
    printf("    p4 (0x80200000) = 0xee000004\n");
    
    printf("\n  Read back values:\n");
    
    printf("    p0 (0x80000000) = ");
    print_hex(*p0);
    printf(" %s\n", *p0 == 0xAA000000 ? "OK" : "ALIASED!");
    
    printf("    p1 (0x80010000) = ");
    print_hex(*p1);
    printf(" %s\n", *p1 == 0xBB000001 ? "OK" : "ALIASED!");
    
    printf("    p2 (0x80020000) = ");
    print_hex(*p2);
    printf(" %s\n", *p2 == 0xCC000002 ? "OK" : "ALIASED!");
    
    printf("    p3 (0x80100000) = ");
    print_hex(*p3);
    printf(" %s\n", *p3 == 0xDD000003 ? "OK" : "ALIASED!");
    
    printf("    p4 (0x80200000) = ");
    print_hex(*p4);
    printf(" %s\n", *p4 == 0xEE000004 ? "OK" : "ALIASED!");
    
    // 测试更小的偏移
    printf("\n[Test 2] Check small offsets\n");
    volatile uint32_t *q0 = (volatile uint32_t *)(PSRAM_BASE + 0x1000);  // 4KB
    volatile uint32_t *q1 = (volatile uint32_t *)(PSRAM_BASE + 0x2000);  // 8KB
    volatile uint32_t *q2 = (volatile uint32_t *)(PSRAM_BASE + 0x4000);  // 16KB
    volatile uint32_t *q3 = (volatile uint32_t *)(PSRAM_BASE + 0x8000);  // 32KB
    
    *q0 = 0x11111111;
    *q1 = 0x22222222;
    *q2 = 0x33333333;
    *q3 = 0x44444444;
    
    printf("    0x80001000 = ");
    print_hex(*q0);
    printf(" (wrote 0x11111111)\n");
    printf("    0x80002000 = ");
    print_hex(*q1);
    printf(" (wrote 0x22222222)\n");
    printf("    0x80004000 = ");
    print_hex(*q2);
    printf(" (wrote 0x33333333)\n");
    printf("    0x80008000 = ");
    print_hex(*q3);
    printf(" (wrote 0x44444444)\n");
    
    printf("\n======================================\n");
    printf("Test completed\n");
    printf("======================================\n");
    
    return 0;
}
