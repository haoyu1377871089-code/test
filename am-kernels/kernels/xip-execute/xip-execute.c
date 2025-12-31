// XIP 执行测试程序
// 直接跳转到 Flash 中执行 char-test (通过 XIP 方式取指)

#include <am.h>
#include <klib-macros.h>

// char-test-xip.bin 在 Flash 中的 XIP 执行地址
// Flash XIP 基地址: 0x30000000
// char-test 偏移: 0x200000 (2MB)
#define FLASH_XIP_CHAR_TEST  0x30200000

int main() {
    putstr("=== XIP Execute Test ===\n");
    putstr("Testing XIP: execute code directly from Flash\n\n");
    
    putstr("Flash XIP address: 0x30200000\n");
    putstr("Jumping to Flash to execute char-test...\n\n");
    
    // 跳转到 Flash XIP 地址执行 char-test
    // char-test 的入口点 _start 位于 0x30200000
    void (*entry)(void) = (void (*)(void))FLASH_XIP_CHAR_TEST;
    
    putstr("--- char-test XIP output ---\n");
    entry();
    
    // 如果 char-test 返回，不会执行到这里
    // 因为 char-test 以 ebreak 结束
    putstr("char-test returned (unexpected)\n");
    
    return 0;
}
