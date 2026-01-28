#include "trap.h"
#include <am.h>
#include <klib.h>

extern Area heap;

static char *hbrk;

void* my_alloc(size_t size) {
  size  = (size + 7) & ~7;  // ROUNDUP to 8
  char *old = hbrk;
  hbrk += size;
  // 检查是否超出 heap 范围
  check((uintptr_t)heap.start <= (uintptr_t)hbrk);
  check((uintptr_t)hbrk < (uintptr_t)heap.end);
  return old;
}

int main() {
  // 初始化 hbrk
  hbrk = (char*)(((uintptr_t)heap.start + 7) & ~7);  // ROUNDUP to 8
  
  char *start = hbrk;
  
  // 第一次分配 400 字节
  int *data1 = my_alloc(100 * sizeof(int));
  check(data1 != NULL);
  check((char*)hbrk - start == 400);
  
  // 重置
  hbrk = start;
  
  // 再次分配 400 字节
  int *data2 = my_alloc(100 * sizeof(int));
  check(data2 != NULL);
  check((char*)hbrk - start == 400);
  
  // 验证 mlim 检查 (1KB = 1024)
  check((uintptr_t)hbrk - (uintptr_t)start <= 1024);
  
  return 0;
}
