// simple.c - 最简单的测试，不包含 UART 初始化延迟
// 只执行基本运算，然后通过 ebreak 退出

int main() {
    volatile int a = 10;
    volatile int b = 20;
    volatile int c = a + b;  // c = 30
    
    // 使用 ebreak 退出，返回值 = c - 30（成功时为 0）
    return c - 30;
}
