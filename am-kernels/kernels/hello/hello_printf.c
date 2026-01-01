#include <am.h>
#include <klib-macros.h>
#include <klib.h>

int main(const char *args) {
  putch('A'); putch('\n');
  printf("Hello from printf!\n");
  putch('B'); putch('\n');
  printf("Testing integers: %d, %d, %d\n", 1, 2, 3);
  putch('C'); putch('\n');
  return 0;
}
