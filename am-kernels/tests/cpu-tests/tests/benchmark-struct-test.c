#include "trap.h"
#include <am.h>
#include <klib.h>

typedef struct Setting {
  int size;
  unsigned long mlim, ref;
  uint32_t checksum;
} Setting;

typedef struct Benchmark {
  void (*prepare)();
  void (*run)();
  int (*validate)();
  const char *name, *desc;
  Setting settings[4];
} Benchmark;

static void dummy_prepare() {}
static void dummy_run() {}
static int dummy_validate() { return 1; }

// QSORT settings
#define QSORT_S {100, 1024, 0, 0x08467105}
#define QSORT_M {30000, 131072, 0, 0xa3e99fe4}
#define QSORT_L {100000, 655360, 4404, 0xed8cff89}
#define QSORT_H {4000000, 16777216, 227620, 0xe6178735}

static Benchmark benchmarks[] = {
  {
    .prepare = dummy_prepare,
    .run = dummy_run,
    .validate = dummy_validate,
    .name = "qsort",
    .desc = "Quick sort",
    .settings = {QSORT_S, QSORT_M, QSORT_L, QSORT_H},
  },
};

extern Area heap;
static char *hbrk;

void* my_alloc(size_t size) {
  size  = (size + 7) & ~7;
  char *old = hbrk;
  hbrk += size;
  return old;
}

int main() {
  // 验证 Setting 结构大小
  check(sizeof(Setting) == 16);  // 4 + 4 + 4 + 4 = 16
  
  // 验证 settings 数组
  Benchmark *bench = &benchmarks[0];
  Setting *setting = &bench->settings[0];  // QSORT_S
  
  check(setting->size == 100);
  check(setting->mlim == 1024);
  check(setting->ref == 0);
  check(setting->checksum == 0x08467105);
  
  // 模拟 bench_reset
  hbrk = (char*)(((uintptr_t)heap.start + 7) & ~7);
  char *start = hbrk;
  
  // 模拟 qsort prepare
  int N = setting->size;  // 100
  int *data = my_alloc(N * sizeof(int));  // 400 bytes
  
  // 验证分配后的偏移
  uintptr_t offset = (uintptr_t)hbrk - (uintptr_t)start;
  check(offset == 400);
  check(offset <= setting->mlim);  // 400 <= 1024
  
  // 写入数据验证
  for (int i = 0; i < N; i++) {
    data[i] = i;
  }
  for (int i = 0; i < N; i++) {
    check(data[i] == i);
  }
  
  return 0;
}
