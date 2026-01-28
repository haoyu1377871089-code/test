#include "trap.h"
#include <stdint.h>
#include <klib-macros.h>

// Simulating microbench's bench_alloc
static char *hbrk;
static uintptr_t mlim = 1024;  // 1 KB for test setting

void* my_alloc(int size) {
    size = (int)ROUNDUP(size, 8);
    char *old = hbrk;
    hbrk += size;
    
    // First assertion
    char *heap_start = (char *)heap.start;
    char *heap_end = (char *)heap.end;
    if (!((uintptr_t)heap_start <= (uintptr_t)hbrk && (uintptr_t)hbrk < (uintptr_t)heap_end)) {
        check(0);  // Fail
    }
    
    // Clear memory
    for (uint64_t *p = (uint64_t *)old; p != (uint64_t *)hbrk; p++) {
        *p = 0;
    }
    
    // Second assertion - the one that fails in microbench
    uintptr_t allocated = (uintptr_t)hbrk - (uintptr_t)heap_start;
    if (allocated > mlim) {
        // Print some debug info
        check(0);  // Fail
    }
    
    return old;
}

void my_reset() {
    hbrk = (char *)ROUNDUP(heap.start, 8);
}

// Simple random number generator
static uint32_t seed = 1;

void my_srand(uint32_t _seed) {
    seed = _seed & 0x7fff;
}

uint32_t my_rand() {
    seed = (seed * (uint32_t)214013L + (uint32_t)2531011L);
    return (seed >> 16) & 0x7fff;
}

// Simulate qsort prepare
#define N 100  // QSORT_S size

int main() {
    // Reset like bench_reset
    my_reset();
    
    // Like bench_qsort_prepare
    my_srand(1);
    
    int *data = (int *)my_alloc(N * sizeof(int));  // 400 bytes
    
    // If we get here, allocation succeeded
    for (int i = 0; i < N; i++) {
        int a = my_rand();
        int b = my_rand();
        data[i] = (a << 16) | b;
    }
    
    // Verify some values
    check(data != (void *)0);
    check(data[0] != 0);  // Should have been filled with random values
    
    return 0;
}
