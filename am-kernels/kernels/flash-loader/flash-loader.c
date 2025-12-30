// Flash Loader: 从 Flash 加载程序到 SRAM 并执行
// 
// 1. 通过 SPI 从 Flash 读取 char-test 二进制
// 2. 将其复制到 SRAM
// 3. 跳转到 SRAM 执行

#include <am.h>
#include <klib-macros.h>

// 声明 AM 提供的 flash_read 函数
extern uint32_t flash_read(uint32_t addr);

// Flash 中 char-test 的存储位置
// 使用 Flash 偏移 0x00200000 (2MB 处)
#define FLASH_CHAR_TEST_OFFSET  0x00200000

// SRAM 加载地址 (char-test 编译时指定的地址)
#define SRAM_LOAD_ADDR          0x0f000800

// char-test 的最大大小 (预估 1KB 足够)
#define CHAR_TEST_MAX_SIZE      1024

// 打印十六进制数
static void print_hex(uint32_t val) {
    const char hex[] = "0123456789ABCDEF";
    putstr("0x");
    for (int i = 7; i >= 0; i--) {
        putch(hex[(val >> (i * 4)) & 0xF]);
    }
}

int main(const char *args) {
    putstr("=== Flash Loader ===\n");
    putstr("Loading char-test from Flash to SRAM...\n\n");

    // 显示加载信息
    putstr("Flash offset: ");
    print_hex(FLASH_CHAR_TEST_OFFSET);
    putstr("\n");
    
    putstr("SRAM address: ");
    print_hex(SRAM_LOAD_ADDR);
    putstr("\n");
    
    putstr("Max size: ");
    print_hex(CHAR_TEST_MAX_SIZE);
    putstr(" bytes\n\n");

    // 从 Flash 读取数据到 SRAM
    putstr("Reading from Flash...\n");
    
    uint32_t *sram_ptr = (uint32_t *)SRAM_LOAD_ADDR;
    uint32_t flash_offset = FLASH_CHAR_TEST_OFFSET;
    
    for (int i = 0; i < CHAR_TEST_MAX_SIZE / 4; i++) {
        uint32_t data = flash_read(flash_offset);
        sram_ptr[i] = data;
        flash_offset += 4;
    }
    
    putstr("Load complete!\n\n");

    // 验证第一条指令 (应该是 lui sp, xxx 或类似)
    putstr("First instruction at SRAM: ");
    print_hex(sram_ptr[0]);
    putstr("\n");
    
    putstr("Jumping to SRAM...\n\n");
    putstr("--- char-test output ---\n");

    // 跳转到 SRAM 执行
    // 使用函数指针跳转
    void (*entry)(void) = (void (*)(void))SRAM_LOAD_ADDR;
    entry();

    // 不应该到达这里
    putstr("ERROR: Returned from char-test!\n");
    return 1;
}
