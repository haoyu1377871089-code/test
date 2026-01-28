#include "trap.h"

// 模拟 microbench 中的 setting 结构体
typedef struct {
    const char *name;
    unsigned int mlim;
    unsigned int ref;
} Setting;

Setting test_setting = {
    .name = "test",
    .mlim = 1024,
    .ref = 100
};

Setting *setting = &test_setting;

// 测试连续 load 指令（第二条依赖第一条的结果）
int main() {
    // 第一次加载 setting 指针，然后加载 mlim
    unsigned int mlim = setting->mlim;
    check(mlim == 1024);
    
    // 再次测试，确保值一致
    unsigned int mlim2 = setting->mlim;
    check(mlim2 == 1024);
    
    // 测试 ref 字段
    unsigned int ref = setting->ref;
    check(ref == 100);
    
    // 测试 name 指针
    const char *name = setting->name;
    check(name[0] == 't');
    check(name[1] == 'e');
    check(name[2] == 's');
    check(name[3] == 't');
    
    return 0;
}
