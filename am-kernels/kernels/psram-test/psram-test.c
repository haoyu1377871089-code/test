#include <am.h>
#include <klib.h>
#include <klib-macros.h>

// PSRAM base address
#define PSRAM_BASE 0x80000000

int main(const char *args) {
  putstr("=== PSRAM Read/Write Test ===\n");
  
  volatile uint32_t *psram = (volatile uint32_t *)PSRAM_BASE;
  
  // Test 1: Simple write and read
  putstr("Test 1: Single word write/read... ");
  psram[0] = 0xDEADBEEF;
  if (psram[0] == 0xDEADBEEF) {
    putstr("PASS\n");
  } else {
    putstr("FAIL\n");
    printf("Expected 0xDEADBEEF, got 0x%08x\n", psram[0]);
    return 1;
  }
  
  // Test 2: Multiple words
  putstr("Test 2: Multiple words... ");
  for (int i = 0; i < 16; i++) {
    psram[i] = (uint32_t)i * 0x01010101U;
  }
  int fail = 0;
  for (int i = 0; i < 16; i++) {
    if (psram[i] != (uint32_t)i * 0x01010101U) {
      fail = 1;
      printf("Mismatch at index %d: expected 0x%08x, got 0x%08x\n", 
             i, (uint32_t)i * 0x01010101U, psram[i]);
    }
  }
  if (!fail) {
    putstr("PASS\n");
  } else {
    putstr("FAIL\n");
    return 1;
  }
  
  // Test 3: Test data section (which is in PSRAM)
  putstr("Test 3: Static data... ");
  static int test_data[4] = {0x12345678, 0x9ABCDEF0, 0x55AA55AA, 0xAA55AA55};
  if (test_data[0] == 0x12345678 && 
      test_data[1] == 0x9ABCDEF0 &&
      test_data[2] == 0x55AA55AA &&
      test_data[3] == 0xAA55AA55) {
    putstr("PASS\n");
  } else {
    putstr("FAIL\n");
    printf("Data mismatch: %08x %08x %08x %08x\n",
           test_data[0], test_data[1], test_data[2], test_data[3]);
    return 1;
  }
  
  putstr("=== All PSRAM tests passed! ===\n");
  return 0;
}
