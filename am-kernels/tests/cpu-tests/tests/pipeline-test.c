#include "trap.h"

// 测试 store/load 指令是否被正确执行
// 测试分支指令是否只执行一次

volatile int counter = 0;
volatile int store_test[10];

int main() {
    // 测试1: store/load 连续执行
    // 如果 store 被跳过，后续 load 会读到错误的值
    store_test[0] = 0;
    for (int i = 0; i < 5; i++) {
        int old = store_test[0];  // load
        store_test[0] = old + 1;  // store
    }
    check(store_test[0] == 5);  // 应该是 5
    
    // 测试2: 分支中的 store/load
    // 模拟 uart_init 的延迟循环
    volatile int loop_var = 0;
    int loop_count = 0;
    while (loop_var < 100) {
        loop_var = loop_var + 1;  // load, add, store
        loop_count++;
    }
    check(loop_var == 100);
    check(loop_count == 100);  // 如果分支重复执行，这个值会不对
    
    // 测试3: 更复杂的 store/load 模式
    int a = 0, b = 0, c = 0;
    for (int i = 0; i < 10; i++) {
        a = a + 1;
        b = b + 2;
        c = a + b;
    }
    check(a == 10);
    check(b == 20);
    check(c == 30);
    
    // 测试4: 函数调用中的 store/load
    counter = 0;
    for (int i = 0; i < 3; i++) {
        counter++;
    }
    check(counter == 3);
    
    return 0;
}
