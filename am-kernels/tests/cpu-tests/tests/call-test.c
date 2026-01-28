#include "trap.h"

// Test function calls and returns
static int call_count = 0;

__attribute__((noinline))
void simple_func(void) {
    call_count++;
}

__attribute__((noinline))
int add_func(int a, int b) {
    return a + b;
}

__attribute__((noinline))
int nested_func(int n) {
    if (n <= 0) return 0;
    return n + nested_func(n - 1);
}

int main() {
    // Test 1: Simple call
    call_count = 0;
    simple_func();
    check(call_count == 1);
    
    // Test 2: Call with args and return value
    int result = add_func(3, 4);
    check(result == 7);
    
    // Test 3: Multiple calls
    call_count = 0;
    for (int i = 0; i < 5; i++) {
        simple_func();
    }
    check(call_count == 5);
    
    // Test 4: Nested calls (recursion)
    int sum = nested_func(5);  // 5 + 4 + 3 + 2 + 1 + 0 = 15
    check(sum == 15);
    
    return 0;
}
