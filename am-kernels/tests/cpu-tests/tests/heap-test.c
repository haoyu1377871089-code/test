#include "trap.h"
#include <am.h>

int main() {
  // 测试 heap 分配
  extern Area heap;
  
  // 打印 heap 范围
  char *heap_start = (char*)heap.start;
  (void)heap.end;  // 避免未使用警告
  
  // 基本写入测试
  volatile int *p = (volatile int*)heap_start;
  *p = 0x12345678;
  check(*p == 0x12345678);
  
  // 边界写入测试
  p = (volatile int*)(heap_start + 1024);
  *p = 0xDEADBEEF;
  check(*p == 0xDEADBEEF);
  
  // 指针运算测试
  char *ptr = heap_start;
  ptr += 400;  // 400 字节偏移
  check((char*)ptr - (char*)heap_start == 400);
  
  ptr = heap_start + 1024;  // 1KB 偏移
  check((char*)ptr - (char*)heap_start == 1024);
  
  return 0;
}
