#include "trap.h"
#include <am.h>
#include <klib.h>

typedef struct Setting {
  int size;
  unsigned long mlim, ref;
  uint32_t checksum;
} Setting;

// QSORT_S {100, 1 KB, 0, 0x08467105}
static Setting settings[] = {
  {100, 1024, 0, 0x08467105},
  {30000, 131072, 0, 0xa3e99fe4},
};

int main() {
  Setting *setting = &settings[0];
  
  // 验证结构成员
  check(setting->size == 100);
  check(setting->mlim == 1024);
  check(setting->ref == 0);
  check(setting->checksum == 0x08467105);
  
  // 验证第二个设置
  setting = &settings[1];
  check(setting->size == 30000);
  check(setting->mlim == 131072);
  
  return 0;
}
