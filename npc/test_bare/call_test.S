# call_test.S - 测试函数调用和返回
# 简单的 jal/ret 序列（RV32E 兼容）

.section .text
.globl _start
_start:
    # 设置栈指针
    lui sp, 0x0f002
    
    # 测试 1: 简单的 jal/ret
    li t0, 0           # t0 = 0
    jal test_func1     # 调用 test_func1，t0 应该变成 1
    
    # 返回后检查 t0
    li t1, 1
    bne t0, t1, fail   # 如果 t0 != 1，失败
    
    # 测试 2: 带栈操作的函数调用
    li a0, 10
    jal test_func2     # 调用 test_func2，a0 应该变成 20
    
    li t1, 20
    bne a0, t1, fail   # 如果 a0 != 20，失败
    
    # 测试 3: 嵌套调用（非递归）
    li a0, 5
    jal outer_func     # outer_func 调用 inner_func
    
    li t1, 15          # outer 加 5，inner 加 5
    bne a0, t1, fail
    
pass:
    li a0, 0
    j exit
    
fail:
    li a0, 1
    
exit:
    ebreak
    j exit

# 简单函数：设置 t0 = 1
test_func1:
    li t0, 1
    ret

# 带栈操作的函数：a0 = a0 * 2
test_func2:
    addi sp, sp, -4
    sw a0, 0(sp)       # 保存原始值
    lw t0, 0(sp)       # 加载回来
    add a0, t0, t0     # a0 = t0 * 2
    addi sp, sp, 4
    ret

# 嵌套调用：outer_func 调用 inner_func
outer_func:
    addi sp, sp, -4
    sw ra, 0(sp)       # 保存返回地址
    
    addi a0, a0, 5     # a0 += 5
    jal inner_func     # a0 += 5
    
    lw ra, 0(sp)       # 恢复返回地址
    addi sp, sp, 4
    ret

inner_func:
    addi a0, a0, 5     # a0 += 5
    ret
