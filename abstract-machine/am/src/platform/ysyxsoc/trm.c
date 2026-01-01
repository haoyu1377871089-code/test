#include <am.h>
#include <klib-macros.h>

extern char _heap_start;
extern char _heap_end;
extern char _stack_pointer;
int main(const char *args);

// MAINARGS 支持
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER);

#define STACK_SIZE 0x1000
// Heap 在 PSRAM 中，从 _heap_start 到 _heap_end
Area heap = RANGE(&_heap_start, &_heap_end);

#define UART_BASE 0x10000000L
// UART 16550 寄存器偏移 - ysyxSoC 使用 4 字节对齐
#define UART_TX   (0 * 4)   // 发送寄存器 / 接收缓冲
#define UART_LSR  (5 * 4)   // 行状态寄存器
#define UART_LCR  (3 * 4)   // 行控制寄存器
#define UART_DLL  (0 * 4)   // 除数锁存器低字节 (DLAB=1)
#define UART_DLM  (1 * 4)   // 除数锁存器高字节 (DLAB=1)

void uart_init() {
  // 确保足够的延迟让硬件稳定
  for (volatile int i = 0; i < 1000; i++);
  
  // Set DLAB=1 to access divisor registers (LCR bit 7)
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = 0x80; 
  for (volatile int i = 0; i < 1000; i++);
  
  // Set divisor = 1 for maximum baud rate
  // dl > 0 is required for enable signal
  *(volatile uint8_t *)(UART_BASE + UART_DLL) = 0x01;
  for (volatile int i = 0; i < 500; i++);
  *(volatile uint8_t *)(UART_BASE + UART_DLM) = 0x00;
  for (volatile int i = 0; i < 500; i++);
  
  // Clear DLAB, set 8N1 format (8 data bits, no parity, 1 stop bit)
  *(volatile uint8_t *)(UART_BASE + UART_LCR) = 0x03;
  for (volatile int i = 0; i < 1000; i++);
}

void putch(char ch) {
  // 等待发送器准备好 (THRE=1 表示 TX FIFO 为空)
  while ((*(volatile uint8_t *)(UART_BASE + UART_LSR) & 0x20) == 0);
  
  // Write character to TX register
  *(volatile uint8_t *)(UART_BASE + UART_TX) = ch;
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

// 读取CSR寄存器
static inline uint32_t csrr_mvendorid() {
  uint32_t val;
  asm volatile("csrr %0, mvendorid" : "=r"(val));
  return val;
}

static inline uint32_t csrr_marchid() {
  uint32_t val;
  asm volatile("csrr %0, marchid" : "=r"(val));
  return val;
}

// 输出十六进制数
static void print_hex(uint32_t val) {
  putch('0'); putch('x');
  for (int i = 28; i >= 0; i -= 4) {
    int digit = (val >> i) & 0xF;
    putch(digit < 10 ? '0' + digit : 'a' + digit - 10);
  }
}

void _trm_init() {
  uart_init();
  
  // 输出学号信息
  uint32_t mvendorid = csrr_mvendorid();
  uint32_t marchid = csrr_marchid();
  
  // 输出 mvendorid
  putch('m'); putch('v'); putch('e'); putch('n'); putch('d'); putch('o'); putch('r'); putch('i'); putch('d'); putch('=');
  print_hex(mvendorid);
  putch(' '); putch('(');
  // 输出 ASCII 字符 "ysyx"
  putch((mvendorid >> 24) & 0xFF);
  putch((mvendorid >> 16) & 0xFF);
  putch((mvendorid >> 8) & 0xFF);
  putch(mvendorid & 0xFF);
  putch(')'); putch('\n');
  
  // 输出 marchid
  putch('m'); putch('a'); putch('r'); putch('c'); putch('h'); putch('i'); putch('d'); putch('=');
  print_hex(marchid);
  putch('\n');
  
  // 拷贝数据段（从 Flash 到 PSRAM）
  uint32_t *src = (uint32_t *)&_data_load_addr;
  uint32_t *dst = (uint32_t *)&_data;
  uint32_t *end = (uint32_t *)&_edata;
  while (dst < end) { *dst++ = *src++; }
  
  // 清零 BSS 段
  dst = (uint32_t *)&_bss_start;
  end = (uint32_t *)&_bss_end;
  while (dst < end) { *dst++ = 0; }
  
  int ret = main(mainargs);
  halt(ret);
}