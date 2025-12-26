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
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = 0x80; // LCR.DLAB = 1
  *(volatile uint8_t *)(UART_BASE + UART_DLL) = 0x1;  // DLL = 1
  *(volatile uint8_t *)(UART_BASE + UART_DLM) = 0x0;  // DLM = 0
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = 0x03; // LCR.DLAB = 0, 8N1
}

void putch(char ch) {
  *(volatile char *)(UART_BASE + UART_TX) = ch;
}

void halt(int code) {
  asm volatile("ebreak");
  while (1);
}

extern char _data_load_addr;
extern char _data;
extern char _edata;
extern char _bss_start;
extern char _bss_end;

void putch(char ch);

void _trm_init() {
  uart_init();
  // Copy .data
  uint32_t *src = (uint32_t *)&_data_load_addr;
  uint32_t *dst = (uint32_t *)&_data;
  uint32_t *end = (uint32_t *)&_edata;
  
  while (dst < end) {
    *dst++ = *src++;
  }

  // Clear .bss
  dst = (uint32_t *)&_bss_start;
  end = (uint32_t *)&_bss_end;
  while (dst < end) {
    *dst++ = 0;
  }

  int ret = main("");
  halt(ret);
}
