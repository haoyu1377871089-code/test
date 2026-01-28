#include "trap.h"
#include <klib.h>
#include <stdint.h>

// Test printf operations like microbench uses
int main() {
    // Simple prints
    printf("Test 1: Hello\n");
    
    // Print numbers
    printf("Test 2: %d\n", 42);
    printf("Test 3: 0x%x\n", 0xDEAD);
    
    // Print strings
    const char *s = "world";
    printf("Test 4: %s\n", s);
    
    // Print from memory
    static int arr[5] = {1, 2, 3, 4, 5};
    printf("Test 5: arr[2] = %d\n", arr[2]);
    
    // Complex format
    printf("Test 6: x=%d, y=0x%x, s=%s\n", 100, 0xFF, "ok");
    
    // Loop with printf
    for (int i = 0; i < 3; i++) {
        printf("Loop %d\n", i);
    }
    
    return 0;
}
