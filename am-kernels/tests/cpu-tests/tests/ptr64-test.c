#include "trap.h"
#include <stdint.h>
#include <klib-macros.h>

// Test 64-bit pointer operations as used in bench_alloc
static char *hbrk;

int main() {
    // Reset
    hbrk = (char *)ROUNDUP(heap.start, 8);
    
    // Allocate 400 bytes like qsort
    int size = (int)ROUNDUP(400, 8);
    char *old = hbrk;
    hbrk += size;
    
    // Clear memory using uint64_t pointer (like bench_alloc does)
    uint64_t *p = (uint64_t *)old;
    uint64_t *end = (uint64_t *)hbrk;
    
    while (p != end) {
        *p = 0;  // 64-bit store
        p++;     // pointer increment
    }
    
    // Verify the memory was cleared
    for (int i = 0; i < size; i++) {
        check(old[i] == 0);
    }
    
    // Check hbrk is correct
    uintptr_t heap_start = (uintptr_t)ROUNDUP(heap.start, 8);
    uintptr_t allocated = (uintptr_t)hbrk - heap_start;
    check(allocated == 400);
    
    return 0;
}
