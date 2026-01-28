# raw_test.S - 测试 RAW 数据冒险处理
# 连续的 add 指令形成 RAW 依赖链

.section .text
.globl _start
_start:
    # 设置栈指针
    lui sp, 0x0f002

    # 测试 1: 连续 RAW 依赖 (EX->ID)
    li t0, 1
    add t0, t0, t0     # t0 = 2  (依赖上一条)
    add t0, t0, t0     # t0 = 4  (依赖上一条)
    add t0, t0, t0     # t0 = 8  (依赖上一条)
    add t0, t0, t0     # t0 = 16 (依赖上一条)
    
    li t1, 16
    bne t0, t1, fail   # 检查结果
    
    # 测试 2: load-use 冒险 (MEM->ID)
    li t0, 42
    sw t0, -4(sp)      # 存储 42
    lw t1, -4(sp)      # load t1 = 42
    addi t2, t1, 1     # t2 = t1 + 1 = 43 (load-use 依赖)
    
    li a1, 43
    bne t2, a1, fail   # 检查结果
    
pass:
    li a0, 0
    j exit
    
fail:
    li a0, 1
    
exit:
    ebreak
    j exit
