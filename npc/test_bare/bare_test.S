# bare_test.S - 裸机测试，直接验证流水线
# 不使用任何库或延迟，直接执行基本操作然后退出
# 仅使用 RV32E 支持的寄存器 (x0-x15): zero,ra,sp,gp,tp,t0,t1,t2,s0,s1,a0-a5

.section .text
.globl _start
_start:
    # 初始化寄存器
    li t0, 10        # t0 = 10
    li t1, 20        # t1 = 20
    add t2, t0, t1   # t2 = 30
    
    # 测试分支
    li a1, 30        # a1 = 30 (用 a1 替代 t3)
    beq t2, a1, pass # 如果 t2 == 30，跳转到 pass
    
fail:
    li a0, 1         # 返回值 1 表示失败
    j exit
    
pass:
    li a0, 0         # 返回值 0 表示成功
    
exit:
    ebreak           # 使用 ebreak 退出仿真
    j exit           # 永不到达
