#include <am.h>
#include <klib-macros.h>
#include <klib.h>

// 使用全局变量（会在 BSS/DATA 段，位于 PSRAM）
static char global_buf[100];

int main(const char *args) {
  putch('A'); putch('\n');
  
  volatile char *p = (volatile char *)global_buf;
  
  // 测试字节写入
  p[0] = 'H';
  p[1] = 'e';
  p[2] = 'l';
  p[3] = 'l';
  p[4] = 'o';
  p[5] = '\0';
  
  // 读取并输出
  putch('[');
  for (int i = 0; i < 6; i++) {
    if (p[i] >= 32 && p[i] <= 126) {
      putch(p[i]);
    } else if (p[i] == 0) {
      break;
    } else {
      putch('.');
    }
  }
  putch(']'); putch('\n');
  
  // 使用 putstr 输出
  putch('{');
  putstr(global_buf);
  putch('}'); putch('\n');
  
  return 0;
}
