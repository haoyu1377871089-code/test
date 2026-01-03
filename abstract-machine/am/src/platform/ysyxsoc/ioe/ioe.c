#include <am.h>
#include <klib-macros.h>

// Timer: 使用 CLINT 风格的 mtime 寄存器 (假设在 0x02000000)
#define CLINT_MTIME 0x0200bff8UL

// UART 16550 寄存器定义 (4字节对齐)
#define UART_BASE   0x10000000UL
#define UART_RBR    (UART_BASE + 0 * 4)   // 接收缓冲寄存器 (DLAB=0, 读)
#define UART_LSR    (UART_BASE + 5 * 4)   // 行状态寄存器
#define UART_LSR_DR 0x01                  // 数据就绪位 (Data Ready)

// PS/2 键盘控制器
#define PS2_BASE    0x10011000UL
#define PS2_DATA    (PS2_BASE + 0)        // 扫描码数据寄存器

static uint64_t boot_time = 0;

void __am_timer_init() {
  // 初始化启动时间
  // 注意: ysyxSoC 可能没有 CLINT，这里用简单的计数器模拟
  boot_time = 0;
}

static void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  // 返回自启动以来的微秒数 (简化实现)
  // 使用静态计数器模拟时间
  static uint64_t tick = 0;
  tick += 1000; // 每次调用增加 1ms
  uptime->us = tick;
}

static void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour   = 0;
  rtc->day    = 1;
  rtc->month  = 1;
  rtc->year   = 2025;
}

static void __am_timer_config(AM_TIMER_CONFIG_T *cfg) {
  cfg->present = true;
  cfg->has_rtc = false;
}

static void __am_input_config(AM_INPUT_CONFIG_T *cfg) {
  cfg->present = true;  // PS/2 键盘存在
}

// PS/2 扫描码到 AM 键盘码的映射表 (Set 2 Make Code)
// 普通按键 (非扩展码)
static const int scancode_map[256] = {
  [0x1C] = AM_KEY_A,
  [0x32] = AM_KEY_B,
  [0x21] = AM_KEY_C,
  [0x23] = AM_KEY_D,
  [0x24] = AM_KEY_E,
  [0x2B] = AM_KEY_F,
  [0x34] = AM_KEY_G,
  [0x33] = AM_KEY_H,
  [0x43] = AM_KEY_I,
  [0x3B] = AM_KEY_J,
  [0x42] = AM_KEY_K,
  [0x4B] = AM_KEY_L,
  [0x3A] = AM_KEY_M,
  [0x31] = AM_KEY_N,
  [0x44] = AM_KEY_O,
  [0x4D] = AM_KEY_P,
  [0x15] = AM_KEY_Q,
  [0x2D] = AM_KEY_R,
  [0x1B] = AM_KEY_S,
  [0x2C] = AM_KEY_T,
  [0x3C] = AM_KEY_U,
  [0x2A] = AM_KEY_V,
  [0x1D] = AM_KEY_W,
  [0x22] = AM_KEY_X,
  [0x35] = AM_KEY_Y,
  [0x1A] = AM_KEY_Z,
  [0x45] = AM_KEY_0,
  [0x16] = AM_KEY_1,
  [0x1E] = AM_KEY_2,
  [0x26] = AM_KEY_3,
  [0x25] = AM_KEY_4,
  [0x2E] = AM_KEY_5,
  [0x36] = AM_KEY_6,
  [0x3D] = AM_KEY_7,
  [0x3E] = AM_KEY_8,
  [0x46] = AM_KEY_9,
  [0x0E] = AM_KEY_GRAVE,
  [0x4E] = AM_KEY_MINUS,
  [0x55] = AM_KEY_EQUALS,
  [0x66] = AM_KEY_BACKSPACE,
  [0x0D] = AM_KEY_TAB,
  [0x54] = AM_KEY_LEFTBRACKET,
  [0x5B] = AM_KEY_RIGHTBRACKET,
  [0x5D] = AM_KEY_BACKSLASH,
  [0x58] = AM_KEY_CAPSLOCK,
  [0x4C] = AM_KEY_SEMICOLON,
  [0x52] = AM_KEY_APOSTROPHE,
  [0x5A] = AM_KEY_RETURN,
  [0x12] = AM_KEY_LSHIFT,
  [0x41] = AM_KEY_COMMA,
  [0x49] = AM_KEY_PERIOD,
  [0x4A] = AM_KEY_SLASH,
  [0x59] = AM_KEY_RSHIFT,
  [0x14] = AM_KEY_LCTRL,
  [0x11] = AM_KEY_LALT,
  [0x29] = AM_KEY_SPACE,
  [0x76] = AM_KEY_ESCAPE,
  [0x05] = AM_KEY_F1,
  [0x06] = AM_KEY_F2,
  [0x04] = AM_KEY_F3,
  [0x0C] = AM_KEY_F4,
  [0x03] = AM_KEY_F5,
  [0x0B] = AM_KEY_F6,
  [0x83] = AM_KEY_F7,
  [0x0A] = AM_KEY_F8,
  [0x01] = AM_KEY_F9,
  [0x09] = AM_KEY_F10,
  [0x78] = AM_KEY_F11,
  [0x07] = AM_KEY_F12,
};

// 扩展码 (0xE0 前缀) 到 AM 键盘码的映射
static const int scancode_ext_map[256] = {
  [0x75] = AM_KEY_UP,
  [0x72] = AM_KEY_DOWN,
  [0x6B] = AM_KEY_LEFT,
  [0x74] = AM_KEY_RIGHT,
  [0x70] = AM_KEY_INSERT,
  [0x71] = AM_KEY_DELETE,
  [0x6C] = AM_KEY_HOME,
  [0x69] = AM_KEY_END,
  [0x7D] = AM_KEY_PAGEUP,
  [0x7A] = AM_KEY_PAGEDOWN,
  [0x14] = AM_KEY_RCTRL,
  [0x11] = AM_KEY_RALT,
  [0x1F] = AM_KEY_APPLICATION,  // Left GUI (Windows key)
};

// 状态变量
static int ext_flag = 0;      // 是否检测到扩展码前缀 0xE0
static int release_flag = 0;  // 是否检测到释放码前缀 0xF0

static void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  kbd->keydown = false;
  kbd->keycode = AM_KEY_NONE;
  
  // 循环读取扫描码，直到得到一个完整的按键事件或 FIFO 为空
  while (1) {
    // 读取 PS/2 扫描码
    uint32_t scancode = *(volatile uint32_t *)PS2_DATA;
    if (scancode == 0) {
      // FIFO 为空，无按键
      return;
    }
    
    // 处理扫描码
    if (scancode == 0xE0) {
      // 扩展码前缀，继续读取下一个
      ext_flag = 1;
      continue;
    }
    
    if (scancode == 0xF0) {
      // 释放码前缀，继续读取下一个
      release_flag = 1;
      continue;
    }
    
    // 翻译扫描码
    int keycode;
    if (ext_flag) {
      keycode = scancode_ext_map[scancode & 0xFF];
      ext_flag = 0;
    } else {
      keycode = scancode_map[scancode & 0xFF];
    }
    
    if (keycode != 0) {
      kbd->keycode = keycode;
      kbd->keydown = !release_flag;
    }
    
    release_flag = 0;
    return;  // 处理完一个按键事件，返回
  }
}

// UART 配置：标记 UART 存在
static void __am_uart_config(AM_UART_CONFIG_T *cfg) {
  cfg->present = true;
}

// UART 接收：从 UART16550 读取接收到的字符
static void __am_uart_rx(AM_UART_RX_T *rx) {
  // 检查 LSR 的 Data Ready 位
  uint8_t lsr = *(volatile uint8_t *)UART_LSR;
  if (lsr & UART_LSR_DR) {
    // 有数据可读，读取 RBR
    rx->data = *(volatile uint8_t *)UART_RBR;
  } else {
    // 没有数据，返回 -1
    rx->data = (char)-1;
  }
}

static void fail(void *buf) { panic("access nonexist register"); }

typedef void (*handler_t)(void *buf);
static void *lut[128] = {
  [AM_TIMER_CONFIG] = __am_timer_config,
  [AM_TIMER_RTC   ] = __am_timer_rtc,
  [AM_TIMER_UPTIME] = __am_timer_uptime,
  [AM_INPUT_CONFIG] = __am_input_config,
  [AM_INPUT_KEYBRD] = __am_input_keybrd,
  [AM_UART_CONFIG ] = __am_uart_config,
  [AM_UART_RX     ] = __am_uart_rx,
};

bool ioe_init() {
  for (int i = 0; i < LENGTH(lut); i++)
    if (!lut[i]) lut[i] = fail;
  __am_timer_init();
  return true;
}

void ioe_read (int reg, void *buf) { ((handler_t)lut[reg])(buf); }
void ioe_write(int reg, void *buf) { ((handler_t)lut[reg])(buf); }

void __am_ioe_init() {
  ioe_init();
}
