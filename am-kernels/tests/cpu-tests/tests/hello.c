#include "trap.h"

char *str = "Hello, world! This is a very long string to test UART FIFO overflow protection. If you see this, polling works!\n";
int main() {
  for (char *p = str; *p; p++) {
    putch(*p);
  }
  return 0;
}

