/*
 * LED流水灯测试程序
 * 用于测试ysyxSoC的GPIO控制器与NVBoard的LED接口
 * 
 * GPIO寄存器地址：
 *   LED寄存器   : 0x10002000 (16位，LD0-LD15)
 *   Switch寄存器: 0x10002004 (16位，SW0-SW15，只读)
 *   7段数码管   : 0x10002008 (32位，每4位控制一个数码管)
 */

#include <am.h>
#include <klib.h>
#include <klib-macros.h>

#define GPIO_BASE       0x10002000
#define GPIO_LED        (*(volatile uint16_t *)(GPIO_BASE + 0x0))
#define GPIO_SWITCH     (*(volatile uint16_t *)(GPIO_BASE + 0x4))
#define GPIO_SEG        (*(volatile uint32_t *)(GPIO_BASE + 0x8))

// 软件延时函数
static void delay(int n) {
    volatile int i;
    for (i = 0; i < n; i++) {
        // 空循环
    }
}

// 显示16进制数字到数码管
static void seg_display(uint32_t value) {
    uint32_t seg_val = 0;
    for (int i = 0; i < 8; i++) {
        seg_val |= ((value >> (i * 4)) & 0xF) << (i * 4);
    }
    GPIO_SEG = seg_val;
}

// 密码验证：等待拨码开关状态与密码一致
#define PASSWORD 0x0000  // 密码：全0

static void wait_for_password(void) {
    putstr("=== Password Check ===\n");
    putstr("Please set switches to PASSWORD (0x0000)\n");
    
    uint16_t sw;
    uint32_t check_count = 0;
    
    while (1) {
        sw = GPIO_SWITCH;
        
        // 在数码管上显示当前开关状态
        seg_display(sw);
        
        // 在LED上显示当前开关状态（镜像显示）
        GPIO_LED = sw;
        
        // 每隔一段时间打印状态
        if (check_count % 100 == 0) {
            putstr("SW: 0x");
            for (int i = 12; i >= 0; i -= 4) {
                int nibble = (sw >> i) & 0xF;
                putch(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
            }
            if (sw == PASSWORD) {
                putstr(" <- CORRECT!\n");
            } else {
                putstr(" <- waiting...\n");
            }
        }
        
        // 检查密码是否正确
        if (sw == PASSWORD) {
            putstr("Password correct! Starting LED flow...\n");
            delay(500);  // 短暂延迟让用户看到消息
            break;
        }
        
        check_count++;
        delay(100);
    }
}

int main(const char *args) {
    putstr("LED Flow Light Test\n");
    putstr("GPIO Base: 0x10002000\n");
    
    // 先进行密码验证
    wait_for_password();
    
    uint16_t led_pattern = 0x0001;  // 从LED0开始
    uint32_t counter = 0;
    
    while (1) {
        // 写入LED寄存器
        GPIO_LED = led_pattern;
        
        // 读取开关状态并显示到数码管
        uint16_t sw = GPIO_SWITCH;
        seg_display((counter << 16) | sw);
        
        // 输出状态 (每次都打印以观察流水效果)
        putstr("LED: 0x");
        // 简单的16进制输出
        for (int i = 12; i >= 0; i -= 4) {
            int nibble = (led_pattern >> i) & 0xF;
            putch(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
        }
        putstr(" SW: 0x");
        for (int i = 12; i >= 0; i -= 4) {
            int nibble = (sw >> i) & 0xF;
            putch(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
        }
        putch('\n');
        
        // 左移流水灯
        led_pattern <<= 1;
        if (led_pattern == 0) {
            led_pattern = 0x0001;  // 循环
        }
        
        counter++;
        delay(50);  // 延时（仿真中使用较小值）
    }
    
    return 0;
}
