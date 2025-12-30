#include <am.h>
#include <klib-macros.h>

// SPI 控制器基地址
#define SPI_BASE    0x10001000

// SPI 寄存器偏移 (按照 spi_defines.v)
#define SPI_RX0     (SPI_BASE + 0x00)  // 接收数据寄存器0
#define SPI_TX0     (SPI_BASE + 0x00)  // 发送数据寄存器0
#define SPI_CTRL    (SPI_BASE + 0x10)  // 控制寄存器
#define SPI_DIVIDER (SPI_BASE + 0x14)  // 分频寄存器
#define SPI_SS      (SPI_BASE + 0x18)  // 从设备选择寄存器

// 控制寄存器位定义
#define SPI_CTRL_ASS        (1 << 13)  // 自动SS控制
#define SPI_CTRL_IE         (1 << 12)  // 中断使能
#define SPI_CTRL_LSB        (1 << 11)  // LSB优先
#define SPI_CTRL_TX_NEG     (1 << 10)  // MOSI在下降沿变化
#define SPI_CTRL_RX_NEG     (1 << 9)   // MISO在下降沿采样
#define SPI_CTRL_GO         (1 << 8)   // 开始传输
#define SPI_CTRL_BUSY       (1 << 8)   // 传输中 (与GO共用位)

// bitrev 是 slave 7
#define BITREV_SS   (1 << 7)

// 寄存器读写
static inline void spi_write(uint32_t addr, uint32_t data) {
    *(volatile uint32_t *)addr = data;
}

static inline uint32_t spi_read(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

// 位翻转函数 (软件实现，用于验证)
static inline uint8_t bitrev_sw(uint8_t data) {
    uint8_t result = 0;
    for (int i = 0; i < 8; i++) {
        if (data & (1 << i)) {
            result |= (1 << (7 - i));
        }
    }
    return result;
}

// 通过 SPI 发送数据到 bitrev 并接收结果
uint8_t bitrev_spi(uint8_t data) {
    // 1. 设置发送数据 (高8位是输入，低8位会接收输出)
    spi_write(SPI_TX0, (uint32_t)data << 8);

    // 2. 设置分频器 (最小值使SCK频率最高)
    spi_write(SPI_DIVIDER, 0x0001);

    // 3. 选择 bitrev 作为 slave (SS7)
    spi_write(SPI_SS, BITREV_SS);

    // 4. 设置控制寄存器并启动传输
    // CHAR_LEN = 16 (发送8位+接收8位)
    // ASS = 1 (自动控制SS)
    // TX_NEG = 1 (MOSI在下降沿变化，以便slave在上升沿采样)
    // RX_NEG = 0 (MISO在上升沿采样)
    // LSB = 0 (MSB优先)
    // GO = 1 (开始传输)
    uint32_t ctrl = 16 | SPI_CTRL_ASS | SPI_CTRL_TX_NEG | SPI_CTRL_GO;
    spi_write(SPI_CTRL, ctrl);

    // 5. 等待传输完成 (轮询GO/BUSY位)
    while (spi_read(SPI_CTRL) & SPI_CTRL_BUSY) {
        // busy wait
    }

    // 6. 读取接收到的数据
    uint32_t rx = spi_read(SPI_RX0);
    return (uint8_t)(rx & 0xFF);
}

int main(const char *args) {
    putstr("=== BitRev SPI Test ===\n");

    // 测试用例
    uint8_t test_cases[] = {0x00, 0xFF, 0xA5, 0x5A, 0x0F, 0xF0, 0x12, 0x80};
    int num_tests = sizeof(test_cases);
    int pass_count = 0;

    for (int i = 0; i < num_tests; i++) {
        uint8_t input = test_cases[i];
        uint8_t expected = bitrev_sw(input);
        uint8_t result = bitrev_spi(input);

        if (result == expected) {
            putstr("[PASS] ");
            pass_count++;
        } else {
            putstr("[FAIL] ");
        }
        putstr("Input: 0x");
        putch("0123456789ABCDEF"[(input >> 4) & 0xF]);
        putch("0123456789ABCDEF"[input & 0xF]);
        putstr(" -> Result: 0x");
        putch("0123456789ABCDEF"[(result >> 4) & 0xF]);
        putch("0123456789ABCDEF"[result & 0xF]);
        putstr(" (Expected: 0x");
        putch("0123456789ABCDEF"[(expected >> 4) & 0xF]);
        putch("0123456789ABCDEF"[expected & 0xF]);
        putstr(")\n");
    }

    putstr("\n=== Summary ===\n");
    if (pass_count == num_tests) {
        putstr("*** ALL TESTS PASSED! ***\n");
        return 0;
    } else {
        putstr("*** SOME TESTS FAILED! ***\n");
        halt(1);
        return 1;
    }
}
