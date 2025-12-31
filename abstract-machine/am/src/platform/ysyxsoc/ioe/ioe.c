#include <am.h>
#include <klib-macros.h>

// Timer: 使用 CLINT 风格的 mtime 寄存器 (假设在 0x02000000)
#define CLINT_MTIME 0x0200bff8UL

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
  cfg->present = false;
}

static void __am_input_keybrd(AM_INPUT_KEYBRD_T *kbd) {
  kbd->keydown = false;
  kbd->keycode = AM_KEY_NONE;
}

static void fail(void *buf) { panic("access nonexist register"); }

typedef void (*handler_t)(void *buf);
static void *lut[128] = {
  [AM_TIMER_CONFIG] = __am_timer_config,
  [AM_TIMER_RTC   ] = __am_timer_rtc,
  [AM_TIMER_UPTIME] = __am_timer_uptime,
  [AM_INPUT_CONFIG] = __am_input_config,
  [AM_INPUT_KEYBRD] = __am_input_keybrd,
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
