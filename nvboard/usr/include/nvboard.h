#ifndef __USR_NVBOARD_H__
#define __USR_NVBOARD_H__

// Include pin definitions
#include "pins.h"

// NVBoard user-facing API declarations
void nvboard_init(int vga_clk_cycle = 1);
void nvboard_quit();
void nvboard_bind_pin(void *signal, int len, ...);
void nvboard_update();

#endif
