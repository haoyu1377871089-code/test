#include "trap.h"

// Simple test for load/store operations and pointer arithmetic
static char data[32];

int main() {
    // Test 1: Simple pointer arithmetic
    char *p = data;
    p += 10;
    
    // Test 2: Store and load
    *p = 42;
    int x = *p;
    check(x == 42);
    
    // Test 3: Global pointer update (like hbrk += size)
    static char *hbrk = data;
    int size = 8;
    hbrk += size;
    check(hbrk == data + 8);
    
    // Test 4: Multiple updates
    hbrk += 8;
    check(hbrk == data + 16);
    
    // Test 5: Verify pointer values
    int diff = (int)(hbrk - data);
    check(diff == 16);
    
    return 0;
}
