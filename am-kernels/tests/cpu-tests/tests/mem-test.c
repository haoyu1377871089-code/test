#include "trap.h"

#define N 16

void mem_test() {
  volatile int *p = (int *)(0x0f000000 + 0x800);
  int i;

  putch('S'); // Start

  for(i = 0; i < N; i ++) {
    p[i] = i;
    putch('.');
  }

  putch('W'); // Write done

  for(i = 0; i < N; i ++) {
    check(p[i] == i);
    putch('r');
  }

  putch('D'); // Done
}

int main() {
  mem_test();
  return 0;
}
