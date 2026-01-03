/*
 * UART 接收测试程序
 * 用于测试 ysyxSoC 的 UART RX 功能与 NVBoard 的集成
 * 
 * 使用方法：
 *   1. 运行程序
 *   2. 在 NVBoard 窗口中点击右上角的 UART 终端区域（获取焦点）
 *   3. 在终端区域输入字符
 *   4. 程序会显示接收到的字符
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

// 直接访问 UART 寄存器进行调试
#define UART_BASE   0x10000000UL
#define UART_RBR    (*(volatile uint8_t *)(UART_BASE + 0 * 4))
#define UART_LSR    (*(volatile uint8_t *)(UART_BASE + 5 * 4))
#define UART_LSR_DR 0x01  // Data Ready bit

static void print_hex8(uint8_t val) {
    const char hex[] = "0123456789ABCDEF";
    putch('0'); putch('x');
    putch(hex[(val >> 4) & 0xF]);
    putch(hex[val & 0xF]);
}

int main(const char *args) {
    putstr("UART RX Test Program\n");
    putstr("====================\n\n");
    
    // 检查 UART 是否存在
    bool uart_present = io_read(AM_UART_CONFIG).present;
    putstr("UART present: ");
    putstr(uart_present ? "YES\n" : "NO\n");
    
    if (!uart_present) {
        putstr("ERROR: UART not available!\n");
        return 1;
    }
    
    putstr("\nInstructions:\n");
    putstr("1. Click on the UART terminal area (top-right) in NVBoard\n");
    putstr("2. Type characters in the terminal\n");
    putstr("3. Characters will be echoed here\n");
    putstr("\nWaiting for input...\n\n");
    
    // 先打印一次初始 LSR 状态
    putstr("Initial LSR=");
    print_hex8(UART_LSR);
    putstr("\n");
    
    int char_count = 0;
    int poll_count = 0;
    
    while (1) {
        // 每隔一段时间打印 LSR 状态
        poll_count++;
        if (poll_count % 100000 == 0) {
            uint8_t lsr = UART_LSR;
            if (lsr & UART_LSR_DR) {  // 只有有数据时才打印
                putstr("LSR=");
                print_hex8(lsr);
                putstr(" RBR=");
                print_hex8(UART_RBR);
                putstr("\n");
            }
        }
        
        // 尝试从 UART 读取字符
        char ch = io_read(AM_UART_RX).data;
        
        if (ch != (char)-1) {
            // 收到字符
            char_count++;
            
            // 输出收到的字符信息
            putstr("Got: '");
            if (ch >= 32 && ch < 127) {
                putch(ch);
            } else if (ch == '\n') {
                putstr("\\n");
            } else if (ch == '\r') {
                putstr("\\r");
            } else if (ch == '\b') {
                putstr("\\b");
            } else {
                putstr("?");
            }
            putstr("' (0x");
            // 输出十六进制值
            int hi = (ch >> 4) & 0xF;
            int lo = ch & 0xF;
            putch(hi < 10 ? '0' + hi : 'A' + hi - 10);
            putch(lo < 10 ? '0' + lo : 'A' + lo - 10);
            putstr(")\n");
            
            // 回显字符
            if (ch >= 32 && ch < 127) {
                putch(ch);
            } else if (ch == '\n') {
                putch('\n');
            }
        }
    }
    
    return 0;
}
