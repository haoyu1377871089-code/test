#include "trap.h"
#include <stdint.h>

// Test array copy operation like data section copy
static uint32_t src[256];
static uint32_t dst[256];

int main() {
    // Initialize source
    for (int i = 0; i < 256; i++) {
        src[i] = 0xDEAD0000 + i;
    }
    
    // Copy like data section copy: *dst++ = *src++;
    uint32_t *s = src;
    uint32_t *d = dst;
    uint32_t *end = src + 256;
    
    while (s < end) {
        *d++ = *s++;
    }
    
    // Verify
    for (int i = 0; i < 256; i++) {
        check(dst[i] == 0xDEAD0000 + i);
    }
    
    return 0;
}
