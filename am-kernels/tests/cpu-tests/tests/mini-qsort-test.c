#include "trap.h"
#include <am.h>
#include <klib.h>

// 模拟 microbench 环境
extern Area heap;
static char *hbrk;

typedef struct Setting {
  int size;
  unsigned long mlim, ref;
  uint32_t checksum;
} Setting;

static Setting setting_data = {100, 1024, 0, 0x08467105};
Setting *setting = &setting_data;

void* bench_alloc(size_t size) {
  size  = (size + 7) & ~7;
  char *old = hbrk;
  hbrk += size;
  
  // 关键断言
  if (!((uintptr_t)heap.start <= (uintptr_t)hbrk)) {
    printf("FAIL: hbrk (%p) < heap.start (%p)\n", hbrk, heap.start);
    halt(1);
  }
  if (!((uintptr_t)hbrk < (uintptr_t)heap.end)) {
    printf("FAIL: hbrk (%p) >= heap.end (%p)\n", hbrk, heap.end);
    halt(1);
  }
  
  uintptr_t used = (uintptr_t)hbrk - (uintptr_t)heap.start;
  if (!(used <= setting->mlim)) {
    printf("FAIL: used (%lu) > mlim (%lu)\n", (unsigned long)used, (unsigned long)setting->mlim);
    halt(1);
  }
  
  return old;
}

static uint32_t seed = 1;

void bench_srand(uint32_t _seed) {
  seed = _seed & 0x7fff;
}

uint32_t bench_rand() {
  seed = (seed * (uint32_t)214013L + (uint32_t)2531011L);
  return (seed >> 16) & 0x7fff;
}

// qsort 测试
static int N, *data;

void bench_qsort_prepare() {
  bench_srand(1);
  N = setting->size;
  data = bench_alloc(N * sizeof(int));
  for (int i = 0; i < N; i ++) {
    int a = bench_rand();
    int b = bench_rand();
    data[i] = (a << 16) | b;
  }
}

static void swap(int *a, int *b) {
  int t = *a;
  *a = *b;
  *b = t;
}

static void myqsort(int *a, int l, int r) {
  if (l < r) {
    int p = a[l], pivot = l, j;
    for (j = l + 1; j < r; j ++) {
      if (a[j] < p) {
        swap(&a[++pivot], &a[j]);
      }
    }
    swap(&a[pivot], &a[l]);
    myqsort(a, l, pivot);
    myqsort(a, pivot + 1, r);
  }
}

void bench_qsort_run() {
  myqsort(data, 0, N);
}

uint32_t checksum(void *start, void *end) {
  const uint32_t x = 16777619;
  uint32_t h1 = 2166136261u;
  for (uint8_t *p = (uint8_t*)start; p + 4 < (uint8_t*)end; p += 4) {
    for (int i = 0; i < 4; i ++) {
      h1 = (h1 ^ p[i]) * x;
    }
  }
  // FNV hash mixing
  int32_t hash = (uint32_t)h1;
  hash += hash << 13;
  hash ^= hash >> 7;
  hash += hash << 3;
  hash ^= hash >> 17;
  hash += hash << 5;
  return hash;
}

int bench_qsort_validate() {
  // 检查排序是否正确
  for (int i = 1; i < N; i++) {
    if (data[i-1] > data[i]) {
      printf("Sort error at %d: %d > %d\n", i, data[i-1], data[i]);
      return 0;
    }
  }
  
  uint32_t cs = checksum(data, data + N);
  uint32_t expected = setting->checksum;
  printf("checksum: got=%x, expected=%x\n", cs, expected);
  if (cs != expected) {
    printf("Mismatch! diff=%x\n", cs ^ expected);
  }
  return cs == expected;
}

int main() {
  printf("Starting mini qsort test\n");
  
  // 模拟 bench_reset
  hbrk = (char*)(((uintptr_t)heap.start + 7) & ~7);
  
  printf("heap.start=%p, heap.end=%p, hbrk=%p\n", heap.start, heap.end, hbrk);
  printf("setting: size=%d, mlim=%d, checksum=%x\n", setting->size, (int)setting->mlim, setting->checksum);
  
  // 运行 qsort 测试
  bench_qsort_prepare();
  printf("Prepare done, N=%d, data=%p\n", N, data);
  
  bench_qsort_run();
  printf("Run done\n");
  
  int pass = bench_qsort_validate();
  printf("Validate: %s\n", pass ? "PASS" : "FAIL");
  
  check(pass);
  return 0;
}
