#include "trap.h"
#include <am.h>
#include <stdint.h>

// Test IO timer reading like microbench does
int main() {
    // Read timer multiple times
    uint64_t t1 = io_read(AM_TIMER_UPTIME).us;
    
    // Do some work
    volatile int sum = 0;
    for (int i = 0; i < 1000; i++) {
        sum += i;
    }
    
    uint64_t t2 = io_read(AM_TIMER_UPTIME).us;
    
    // Timer should have advanced
    check(t2 >= t1);
    check(sum == 499500);  // 0 + 1 + ... + 999
    
    return 0;
}
