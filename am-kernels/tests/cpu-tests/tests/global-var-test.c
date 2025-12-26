#include "trap.h"

int global_a = 0x12345678;
int global_b = 0;

int main() {
  // Check initial value (copied from MROM)
  check(global_a == 0x12345678);
  check(global_b == 0);

  // Check write capability (SRAM)
  global_a = 0xdeadbeef;
  check(global_a == 0xdeadbeef);

  global_b = 0x87654321;
  check(global_b == 0x87654321);

  return 0;
}
