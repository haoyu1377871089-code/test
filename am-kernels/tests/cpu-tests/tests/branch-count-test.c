#include "trap.h"

// 专门测试分支指令是否只执行一次
// 如果分支重复提交，side_effect 的值会不正确

volatile int side_effect = 0;
volatile int branch_count = 0;

// 在分支条件中使用副作用来检测重复执行
int test_branch_side_effect() {
    side_effect = 0;
    
    for (int i = 0; i < 10; i++) {
        // 每次循环，side_effect 应该只增加 1
        side_effect++;
        
        if (i < 5) {
            // do nothing
        }
    }
    
    return side_effect;  // 应该是 10
}

// 测试条件分支中的副作用
int test_conditional_side_effect() {
    int count = 0;
    int x = 0;
    
    for (int i = 0; i < 20; i++) {
        x++;
        if (x > 10) {
            count++;
        }
    }
    
    return count;  // 应该是 10 (当 x = 11, 12, ..., 20 时)
}

// 测试嵌套循环
int test_nested_loop() {
    int total = 0;
    
    for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 5; j++) {
            total++;
        }
    }
    
    return total;  // 应该是 25
}

// 测试 while 循环
int test_while_loop() {
    int i = 0;
    int count = 0;
    
    while (i < 100) {
        i++;
        count++;
    }
    
    return count;  // 应该是 100
}

// 测试 do-while 循环
int test_do_while_loop() {
    int i = 0;
    int count = 0;
    
    do {
        i++;
        count++;
    } while (i < 50);
    
    return count;  // 应该是 50
}

int main() {
    // 测试1: 基本分支副作用
    int r1 = test_branch_side_effect();
    check(r1 == 10);
    
    // 测试2: 条件分支副作用
    int r2 = test_conditional_side_effect();
    check(r2 == 10);
    
    // 测试3: 嵌套循环
    int r3 = test_nested_loop();
    check(r3 == 25);
    
    // 测试4: while 循环
    int r4 = test_while_loop();
    check(r4 == 100);
    
    // 测试5: do-while 循环
    int r5 = test_do_while_loop();
    check(r5 == 50);
    
    return 0;
}
