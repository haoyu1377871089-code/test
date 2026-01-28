# lsu_test.S - 测试 load/store 指令
# 使用 SRAM (0x0f000000) 作为内存空间

.section .text
.globl _start
_start:
    # 设置栈指针到 SRAM
    lui sp, 0x0f002      # sp = 0x0f002000

    # 测试 1: 基本 store/load
    li t0, 0x12345678
    sw t0, -4(sp)        # 存储到栈上
    lw t1, -4(sp)        # 加载回来
    bne t0, t1, fail     # 如果不相等，失败
    
    # 测试 2: 不同大小的存储/加载
    li t0, 0xABCD
    sh t0, -8(sp)        # 存储半字
    lhu t1, -8(sp)       # 加载无符号半字
    li t2, 0xABCD
    bne t1, t2, fail
    
    # 测试 3: 字节存储/加载
    li t0, 0x55
    sb t0, -12(sp)
    lbu t1, -12(sp)
    li t2, 0x55
    bne t1, t2, fail
    
pass:
    li a0, 0             # 返回值 0 表示成功
    j exit
    
fail:
    li a0, 1             # 返回值 1 表示失败
    
exit:
    ebreak
    j exit
