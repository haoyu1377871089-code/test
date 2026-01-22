#include <amtest.h>

static void input_test() {
  printf("Input device test skipped.\n");
}

static void timer_test() {
  AM_TIMER_UPTIME_T uptime;
  uint32_t t0, t1;

  uptime = io_read(AM_TIMER_UPTIME);
  t0 = uptime.us / 1000;

  for (int volatile i = 0; i < 10000000; i ++) ;

  uptime = io_read(AM_TIMER_UPTIME);
  t1 = uptime.us / 1000;

  printf("Loop 10^7 time elapse: %d ms\n", t1 - t0);
}

// 使用堆分配代替静态数组，避免 BSS 初始化开销
static uint8_t *vmem = NULL;
#define VMEM_SIZE (512 << 10)
static inline gpuptr_t to_guest(void *ptr) { return ptr ? (uint8_t *)ptr - vmem : AM_GPU_NULL; }

static void video_test() {
  // 动态分配 vmem
  if (vmem == NULL) {
    vmem = (uint8_t *)heap.start;
    if ((uintptr_t)vmem + VMEM_SIZE > (uintptr_t)heap.end) {
      printf("Not enough heap for vmem!\n");
      return;
    }
  }
  
  AM_GPU_CONFIG_T info = io_read(AM_GPU_CONFIG);
  int w = info.width, h = info.height;
  printf("Screen size: %d x %d\n", w, h);

  struct gpu_canvas *cv = (void *)vmem;

  for (uint8_t *p = (void *)&cv[8]; p != vmem + VMEM_SIZE; p++)
    *p = rand() & 0xff;

  cv[0] = (struct gpu_canvas) {
    .w = -1, .h = -1, .x1 = w / 4, .y1 = 0, .w1 = w / 2, .h1 = h - 100,
    .type = AM_GPU_TEXTURE,
    .texture = (struct gpu_texturedesc) {
      .w = 37, .h = 10,
      .pixels = to_guest(&cv[8]),
    },
    .sibling = to_guest(NULL),
  };

  io_write(AM_GPU_MEMCPY, 0, vmem, VMEM_SIZE);
  io_write(AM_GPU_RENDER, 0);
}

static void storage_test() {
  #define nbytes 512
  static char buf[nbytes];
  AM_DISK_CONFIG_T info = io_read(AM_DISK_CONFIG);
  printf("Storage: %d blocks of %d size. Show first 512 bytes\n", info.blkcnt, info.blksz);
  io_write(AM_DISK_BLKIO, false, buf, 0, nbytes / info.blksz);
  for (uint32_t i = 0; i < nbytes; i += 2) {
    printf("%02x%02x ", buf[i] & 0xff, buf[i+1] & 0xff);
    if ((i+2) % 32 == 0) printf("\n");
  }
}

void devscan() {
  printf("heap = [%08x, %08x)\n", heap.start, heap.end);
  input_test();
  timer_test();
  video_test();
  storage_test();
  printf("Test End!\n");
  while (1);
}
