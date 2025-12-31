// XIP (eXecute In Place) 测试程序
// 测试直接通过指针从 Flash 地址空间读取数据

#include <am.h>
#include <klib-macros.h>

// Flash XIP 地址空间
#define FLASH_XIP_BASE  0x30000000

// 测试数据偏移 (与 memory.cpp 中 flash_init_test_data 一致)
#define TEST_DATA_OFFSET  0x100000

// 测试数据数量
#define TEST_COUNT  16

// 与仿真环境中 memory.cpp 定义的测试模式保持一致
static uint32_t expected_patterns[TEST_COUNT] = {
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

int main() {
    putstr("=== XIP Test ===\n");
    putstr("Testing direct pointer access to Flash...\n\n");
    
    // Flash XIP 测试地址
    volatile uint32_t *flash_ptr = (volatile uint32_t *)(FLASH_XIP_BASE + TEST_DATA_OFFSET);
    
    int pass = 0;
    int fail = 0;
    
    for (int i = 0; i < TEST_COUNT; i++) {
        // 使用与 memory.cpp 一致的期望值
        uint32_t expected = expected_patterns[i];
        
        // 直接通过指针读取 (这会触发 XIP 状态机)
        uint32_t actual = flash_ptr[i];
        
        if (actual == expected) {
            putstr("[PASS] ");
            pass++;
        } else {
            putstr("[FAIL] ");
            fail++;
        }
        
        putstr("Addr=");
        print_hex((uint32_t)&flash_ptr[i]);
        putstr(" Read=");
        print_hex(actual);
        putstr(" Exp=");
        print_hex(expected);
        putstr("\n");
    }
    
    putstr("\n=== XIP Test Result ===\n");
    
    if (fail == 0) {
        putstr("*** ALL TESTS PASSED! ***\n");
        return 0;
    } else {
        putstr("*** SOME TESTS FAILED! ***\n");
        return 1;
    }
}
