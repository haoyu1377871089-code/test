#include <cstdio>
#include <cstdlib>
#include <vector>
#include <mutex>
#include <atomic>
#include <thread>
#include <chrono>
#include <termios.h>
#include <fcntl.h>
#include <unistd.h>
#include <SDL2/SDL.h>

#include "../sim.h"
// 提前定义 Area 以满足 amdev.h 的 NET_RX/NET_TX 等依赖
typedef struct { void *start, *end; } Area;
#include "amdev.h"
#include "devices.h"

// 设备地址定义
#define SERIAL_PORT  0xa00003f8
#define VGACTL_ADDR  0xa0000100
#define KBD_ADDR     0xa0000060
#define RTC_ADDR     0xa0000048
#define SYNC_ADDR    0xa0000104
#define FB_ADDR      0xa1000000

// SDL Scancode → AM 键码映射表，按 AM_KEYS 与 SDL_SCANCODE 同名键对齐
static uint32_t scancode_map[256] = {};
static inline void init_scancode_map() {
  #define SETMAP(key) scancode_map[SDL_SCANCODE_##key] = AM_KEY_##key;
  AM_KEYS(SETMAP)
  #undef SETMAP
}

namespace devices {

// VGA/键盘/RTC/串口状态
static int screen_w = 400;
static int screen_h = 300;
static std::vector<uint32_t> framebuffer; // 0x00RRGGBB

static std::mutex kbd_mtx;
static std::vector<uint32_t> kbd_queue;
static std::atomic<bool> kbd_running{false};

static std::atomic<bool> sim_exit{false};
static int sync_count = 0;
static int exit_after_frames = 120;

static bool use_sdl = false;
static SDL_Window *sdl_win = nullptr;
static SDL_Renderer *sdl_ren = nullptr;
static SDL_Texture *sdl_tex = nullptr;
static std::vector<uint32_t> sdl_pix;

static inline uint64_t get_time_us() {
  static auto start_time = std::chrono::steady_clock::now();
  auto now = std::chrono::steady_clock::now();
  return std::chrono::duration_cast<std::chrono::microseconds>(now - start_time).count();
}

static inline void keyboard_push(bool down, int am_code) {
  uint32_t code = (down ? 0x8000u : 0u) | (uint32_t)am_code;
  std::lock_guard<std::mutex> lock(kbd_mtx);
  kbd_queue.push_back(code);
}

static int map_char_to_am(int c) {
  if (c == 27) return AM_KEY_ESCAPE;
  if (c == ' ') return AM_KEY_SPACE;
  if (c == '\r' || c == '\n') return AM_KEY_RETURN;
  if (c >= 'A' && c <= 'Z') c = c - 'A' + 'a';
  if (c >= 'a' && c <= 'z') return AM_KEY_A + (c - 'a');
  if (c >= '1' && c <= '9') return AM_KEY_1 + (c - '1');
  if (c == '0') return AM_KEY_0;
  return AM_KEY_NONE;
}

static void keyboard_thread_func() {
  termios oldt, newt;
  tcgetattr(STDIN_FILENO, &oldt);
  newt = oldt;
  newt.c_lflag &= ~(ICANON | ECHO);
  tcsetattr(STDIN_FILENO, TCSANOW, &newt);
  int old_flags = fcntl(STDIN_FILENO, F_GETFL, 0);
  fcntl(STDIN_FILENO, F_SETFL, old_flags | O_NONBLOCK);

  while (kbd_running.load()) {
    int c = getchar();
    if (c != EOF) {
      if (c == 27) {
        int c1 = getchar();
        if (c1 == '[') {
          int c2 = getchar();
          int key = AM_KEY_NONE;
          if (c2 == 'A') key = AM_KEY_UP;
          else if (c2 == 'B') key = AM_KEY_DOWN;
          else if (c2 == 'C') key = AM_KEY_RIGHT;
          else if (c2 == 'D') key = AM_KEY_LEFT;
          if (key != AM_KEY_NONE) {
            keyboard_push(true, key);
            keyboard_push(false, key);
            continue;
          }
        }
        keyboard_push(true, AM_KEY_ESCAPE);
        keyboard_push(false, AM_KEY_ESCAPE);
        continue;
      }
      int am_code = map_char_to_am(c);
      if (am_code != AM_KEY_NONE) {
        keyboard_push(true, am_code);
        keyboard_push(false, am_code);
      }
    } else {
      usleep(10000);
    }
  }

  tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
  fcntl(STDIN_FILENO, F_SETFL, old_flags);
}

static void sdl_event_thread_func() {
  while (!sim_exit.load()) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      if (e.type == SDL_QUIT) {
        sim_exit.store(true);
      } else if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP) {
        bool down = (e.type == SDL_KEYDOWN);
        uint8_t sc = (uint8_t)e.key.keysym.scancode;
        uint32_t am_code = scancode_map[sc];
        if (am_code != AM_KEY_NONE) keyboard_push(down, (int)am_code);
      }
    }
    usleep(1000);
  }
}

static void vga_sync_dump() {
  if (use_sdl) {
    for (int y = 0; y < screen_h; y++) {
      for (int x = 0; x < screen_w; x++) {
        uint32_t px = framebuffer[y * screen_w + x];
        sdl_pix[y * screen_w + x] = 0xFF000000 | px;
      }
    }
    SDL_UpdateTexture(sdl_tex, nullptr, sdl_pix.data(), screen_w * 4);
    SDL_RenderClear(sdl_ren);
    SDL_RenderCopy(sdl_ren, sdl_tex, nullptr, nullptr);
    SDL_RenderPresent(sdl_ren);
  }

  sync_count++;
  if (exit_after_frames > 0 && sync_count >= exit_after_frames) {
    sim_exit.store(true);
    printf("达到设定帧数(%d)，请求自动退出。\n", exit_after_frames);
  }
}

void init() {
  static bool initialized = false;
  if (initialized) return;
  initialized = true;
  
  const char* env_w = getenv("NPC_SCREEN_W");
  const char* env_h = getenv("NPC_SCREEN_H");
  if (env_w) { int w = atoi(env_w); if (w > 0) screen_w = w; }
  if (env_h) { int h = atoi(env_h); if (h > 0) screen_h = h; }

  framebuffer.assign(screen_w * screen_h, 0);
  sdl_pix.assign(screen_w * screen_h, 0xFF000000);

  const char* env_frames = getenv("NPC_EXIT_FRAMES");
  if (env_frames) {
    int n = atoi(env_frames);
    if (n > 0) { exit_after_frames = n; }
    printf("自动退出帧数设置: %d\n", exit_after_frames);
  }

  use_sdl = false;
  if (SDL_Init(SDL_INIT_VIDEO) == 0) {
    sdl_win = SDL_CreateWindow("NPC VGA",
                               SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                               screen_w, screen_h,
                               SDL_WINDOW_SHOWN);
    if (sdl_win) {
      sdl_ren = SDL_CreateRenderer(sdl_win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
      if (!sdl_ren) sdl_ren = SDL_CreateRenderer(sdl_win, -1, SDL_RENDERER_SOFTWARE);
      if (sdl_ren) {
        sdl_tex = SDL_CreateTexture(sdl_ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, screen_w, screen_h);
        if (sdl_tex) {
          use_sdl = true;
          init_scancode_map();
          printf("SDL 初始化成功，窗口大小 %dx%d\n", screen_w, screen_h);
        }
      }
    }
    if (!use_sdl) {
      if (sdl_tex) { SDL_DestroyTexture(sdl_tex); sdl_tex = nullptr; }
      if (sdl_ren) { SDL_DestroyRenderer(sdl_ren); sdl_ren = nullptr; }
      if (sdl_win) { SDL_DestroyWindow(sdl_win);  sdl_win = nullptr; }
      SDL_Quit();
      printf("SDL 初始化失败。\n");
    }
  } else {
    printf("SDL 不可用。\n");
  }

  kbd_running.store(true);
  static bool thread_started = false;
  if (!thread_started) {
    thread_started = true;
    if (use_sdl) {
      std::thread th(sdl_event_thread_func);
      th.detach();
    } else {
      std::thread th(keyboard_thread_func);
      th.detach();
    }
  }
}

uint32_t read(uint32_t raddr) {
  if (raddr == VGACTL_ADDR) {
    uint32_t value = ((uint32_t)screen_w << 16) | (uint32_t)screen_h;
    return value;
  }
  if (raddr == KBD_ADDR) {
    std::lock_guard<std::mutex> lock(kbd_mtx);
    if (!kbd_queue.empty()) {
      uint32_t code = kbd_queue.front();
      kbd_queue.erase(kbd_queue.begin());
      return code;
    }
    return 0;
  }
  if (raddr == RTC_ADDR || raddr == RTC_ADDR + 4) {
    uint64_t time_us = get_time_us();
    uint32_t value = (raddr == RTC_ADDR) ? (uint32_t)(time_us & 0xFFFFFFFF) : (uint32_t)(time_us >> 32);
    return value;
  }
  if (raddr >= FB_ADDR && raddr + 3 < FB_ADDR + (uint32_t)(screen_w * screen_h * 4)) {
    uint32_t idx = (raddr - FB_ADDR) / 4;
    return framebuffer[idx];
  }
  return UINT32_MAX; // 表示非设备地址
}

void write(uint32_t waddr, uint32_t wdata, uint8_t wmask) {
  if (waddr == SERIAL_PORT) {
    putchar(wdata & 0xff);
    fflush(stdout);
    return;
  }
  if (waddr == SYNC_ADDR) {
    vga_sync_dump();
    return;
  }
  if (waddr >= FB_ADDR && waddr + 3 < FB_ADDR + (uint32_t)(screen_w * screen_h * 4)) {
    uint32_t idx = (waddr - FB_ADDR) / 4;
    uint32_t old = framebuffer[idx];
    uint32_t newv = old;
    for (int i = 0; i < 4; i++) {
      if ((wmask >> i) & 1) {
        uint32_t mask = 0xffu << (i * 8);
        newv = (newv & ~mask) | (wdata & mask);
      }
    }
    framebuffer[idx] = newv;
    return;
  }
}

bool request_exit() { return sim_exit.load(); }
void set_exit_after_frames(int n) { if (n > 0) exit_after_frames = n; }

} // namespace devices