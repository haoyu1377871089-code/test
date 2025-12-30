// SPI Flash 驱动 for ysyxSoC
// 提供通过 SPI 总线读取 Flash 的功能

#include <am.h>

// SPI 控制器基地址
#define SPI_BASE    0x10001000

// SPI 寄存器偏移
#define SPI_RX0     (SPI_BASE + 0x00)
#define SPI_RX1     (SPI_BASE + 0x04)
#define SPI_TX0     (SPI_BASE + 0x00)
#define SPI_TX1     (SPI_BASE + 0x04)
#define SPI_CTRL    (SPI_BASE + 0x10)
#define SPI_DIVIDER (SPI_BASE + 0x14)
#define SPI_SS      (SPI_BASE + 0x18)

// 控制寄存器位定义
#define SPI_CTRL_ASS        (1 << 13)
#define SPI_CTRL_IE         (1 << 12)
#define SPI_CTRL_LSB        (1 << 11)
#define SPI_CTRL_TX_NEG     (1 << 10)
#define SPI_CTRL_RX_NEG     (1 << 9)
#define SPI_CTRL_GO         (1 << 8)
#define SPI_CTRL_BUSY       (1 << 8)

// Slave 选择
#define FLASH_SS    (1 << 0)  // Flash 是 slave 0
#define BITREV_SS   (1 << 7)  // BitRev 是 slave 7

// Flash 命令
#define FLASH_CMD_READ  0x03

// 寄存器读写
static inline void spi_write(uint32_t addr, uint32_t data) {
    *(volatile uint32_t *)addr = data;
}

static inline uint32_t spi_read(uint32_t addr) {
    return *(volatile uint32_t *)addr;
}

// 字节交换
static inline uint32_t bswap32(uint32_t val) {
    return ((val & 0xFF000000) >> 24) |
           ((val & 0x00FF0000) >> 8)  |
           ((val & 0x0000FF00) << 8)  |
           ((val & 0x000000FF) << 24);
}

// 通过 SPI 从 Flash 读取 32 位数据
// addr: Flash 内部地址 (24位有效)
uint32_t flash_read(uint32_t addr) {
    // Flash 读命令: 8位命令 + 24位地址 + 32位数据 = 64位
    uint32_t cmd_addr = ((uint32_t)FLASH_CMD_READ << 24) | (addr & 0x00FFFFFF);
    
    spi_write(SPI_TX1, cmd_addr);
    spi_write(SPI_TX0, 0x00000000);
    spi_write(SPI_DIVIDER, 0x0001);
    spi_write(SPI_SS, FLASH_SS);
    
    // CHAR_LEN=64, ASS=1, TX_NEG=1, GO=1
    uint32_t ctrl = 64 | SPI_CTRL_ASS | SPI_CTRL_TX_NEG | SPI_CTRL_GO;
    spi_write(SPI_CTRL, ctrl);
    
    while (spi_read(SPI_CTRL) & SPI_CTRL_BUSY);
    
    return bswap32(spi_read(SPI_RX0));
}

// 通过 SPI 进行 bitrev 位翻转
uint8_t bitrev_spi(uint8_t data) {
    spi_write(SPI_TX0, (uint32_t)data << 8);
    spi_write(SPI_DIVIDER, 0x0001);
    spi_write(SPI_SS, BITREV_SS);
    
    // CHAR_LEN=16, ASS=1, TX_NEG=1, GO=1
    uint32_t ctrl = 16 | SPI_CTRL_ASS | SPI_CTRL_TX_NEG | SPI_CTRL_GO;
    spi_write(SPI_CTRL, ctrl);
    
    while (spi_read(SPI_CTRL) & SPI_CTRL_BUSY);
    
    return (uint8_t)(spi_read(SPI_RX0) & 0xFF);
}
