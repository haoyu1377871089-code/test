#include "trap.h"

// 专门测试分支指令后紧跟 store/load 的场景
// 这是之前发现 "store/load 被跳过" 问题的场景

volatile int mem[10];

// 模拟 uart_init 中的延迟循环
// 原问题：sw 和第二个 lw 被跳过
//   lw   a5, 0(sp)      # load i
//   addi a5, a5, 1      # i++
//   sw   a5, 0(sp)      # store i  <-- 被跳过！
//   lw   a5, 0(sp)      # load i   <-- 被跳过！
//   bge  a4, a5, ...    # branch

int test_delay_loop() {
    volatile int i = 0;
    int limit = 50;
    
    // 这个循环会生成类似 uart_init 的代码模式
    while (i < limit) {
        i = i + 1;  // load -> add -> store
    }
    
    return i;
}

// 测试分支后紧跟 store
int test_branch_then_store() {
    int result = 0;
    
    for (int i = 0; i < 10; i++) {
        if (i < 5) {
            mem[i] = i * 2;  // branch taken, then store
        } else {
            mem[i] = i * 3;  // branch not taken, then store
        }
        result += mem[i];
    }
    
    return result;
}

// 测试连续的 load-store-branch 模式
int test_load_store_branch() {
    mem[0] = 0;
    
    for (int i = 0; i < 20; i++) {
        int val = mem[0];      // load
        mem[0] = val + 1;      // store
        if (mem[0] >= 20) {    // load + branch
            break;
        }
    }
    
    return mem[0];
}

// 测试函数调用中的分支（验证 JALR 修复）
int increment(int x) {
    return x + 1;
}

int test_function_call_in_loop() {
    int sum = 0;
    for (int i = 0; i < 10; i++) {
        sum = increment(sum);  // JAL + JALR
    }
    return sum;
}

int main() {
    // 测试1: 延迟循环
    int r1 = test_delay_loop();
    check(r1 == 50);
    
    // 测试2: 分支后紧跟 store
    int r2 = test_branch_then_store();
    // 0*2 + 1*2 + 2*2 + 3*2 + 4*2 + 5*3 + 6*3 + 7*3 + 8*3 + 9*3 = 20 + 105 = 125
    check(r2 == 125);
    
    // 测试3: load-store-branch 模式
    int r3 = test_load_store_branch();
    check(r3 == 20);
    
    // 测试4: 函数调用循环
    int r4 = test_function_call_in_loop();
    check(r4 == 10);
    
    return 0;
}
