#include "trap.h"
#include <stdint.h>
#include <klib-macros.h>

// Simulate bench_alloc behavior using real heap from AM
static char *hbrk;

void* my_alloc(int size) {
    size = (int)ROUNDUP(size, 8);
    char *old = hbrk;
    hbrk += size;
    
    // Clear memory
    for (uint32_t *p = (uint32_t *)old; p != (uint32_t *)hbrk; p++) {
        *p = 0;
    }
    
    return old;
}

void my_reset() {
    hbrk = (char *)ROUNDUP(heap.start, 8);
}

int main() {
    // Test 1: Reset
    my_reset();
    char *heap_start = (char *)ROUNDUP(heap.start, 8);
    check(hbrk == heap_start);
    
    // Test 2: First allocation (like qsort with N=100)
    int *data1 = (int *)my_alloc(100 * sizeof(int));  // 400 bytes
    check(data1 == (int *)heap_start);
    check((uintptr_t)hbrk - (uintptr_t)heap_start == 400);
    
    // Test 3: Reset and allocate again
    my_reset();
    check(hbrk == heap_start);
    
    int *data2 = (int *)my_alloc(100 * sizeof(int));
    check(data2 == (int *)heap_start);
    check((uintptr_t)hbrk - (uintptr_t)heap_start == 400);
    
    // Test 4: Check allocation limit
    check((uintptr_t)hbrk - (uintptr_t)heap_start <= 1024);
    
    return 0;
}
