#include <am.h>
#include <klib-macros.h>

extern char _heap_start;
extern char _stack_pointer;
int main(const char *args);

#define STACK_SIZE 0x1000
Area heap = RANGE(&_heap_start, (char *)&_stack_pointer - STACK_SIZE);

#define UART_BASE 0x10000000L
#define UART_TX   0
#define UART_LSR  5
#define UART_LCR  3
#define UART_DLL  0
#define UART_DLM  1

void uart_init() {
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = 0x80; 
  *(volatile uint8_t *)(UART_BASE + UART_DLL) = 0x1;
  *(volatile uint8_t *)(UART_BASE + UART_DLM) = 0x0;
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = 0x03;
}

void putch(char ch) {
  // Rely on LSU handshake and UART FIFO.
  // Polling LSR is bypassed to eliminate simulation delays.
  *(volatile char *)(UART_BASE + UART_TX) = ch;
}

void halt(int code) {
  asm volatile("ebreak");
  while (1);
}

// Math helpers
uint32_t __udivsi3(uint32_t n, uint32_t d) {
  uint32_t q = 0, r = 0;
  for (int i = 31; i >= 0; i--) {
    r = (r << 1) | ((n >> i) & 1);
    if (r >= d) { r -= d; q |= (1U << i); }
  }
  return q;
}

uint32_t __umodsi3(uint32_t n, uint32_t d) {
  uint32_t r = 0;
  for (int i = 31; i >= 0; i--) {
    r = (r << 1) | ((n >> i) & 1);
    if (r >= d) r -= d;
  }
  return r;
}

uint32_t __mulsi3(uint32_t a, uint32_t b) {
  uint32_t res = 0;
  while (a > 0) {
    if (a & 1) res += b;
    a >>= 1;
    b <<= 1;
  }
  return res;
}

extern char _data_load_addr;
extern char _data;
extern char _edata;
extern char _bss_start;
extern char _bss_end;

void _trm_init() {
  uart_init();
  uint32_t *src = (uint32_t *)&_data_load_addr;
  uint32_t *dst = (uint32_t *)&_data;
  uint32_t *end = (uint32_t *)&_edata;
  while (dst < end) { *dst++ = *src++; }
  dst = (uint32_t *)&_bss_start;
  end = (uint32_t *)&_bss_end;
  while (dst < end) { *dst++ = 0; }
  int ret = main("");
  halt(ret);
}