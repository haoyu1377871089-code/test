#include <am.h>
#include <klib.h>
#include <klib-macros.h>

void putch(char ch);

void puthex(uint32_t val) {
  char hex[] = "0123456789ABCDEF";
  for (int i = 28; i >= 0; i -= 4) {
    putch(hex[(val >> i) & 0xF]);
  }
  putch('\n');
}

int main() {
  putch('1');
  volatile uint32_t *flash = (uint32_t *)0x30000000;
  uint32_t data = *flash;
  putch('2');
  
  if (data == 0xdeadbeef) putch('P');
  else putch('F');
  putch('\n');
  
  return 0;
}
