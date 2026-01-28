.text
.globl _start
_start:
    lui sp, 0x0f002

    lui a0, 0x80000
    li t0, 42
    sw t0, 0(a0)
    
    lw t0, 0(a0)
    li t1, 42
    bne t0, t1, print_n
    
    li a1, 89
    j after_first_check
    
print_n:
    li a1, 78
    
after_first_check:
    li t0, 123
    sw t0, 0(a0)
    
    lw t0, 0(a0)
    li t1, 123
    bne t0, t1, print_f
    
    li a2, 71
    j done
    
print_f:
    li a2, 70
    
done:
    li t0, 89
    bne a1, t0, fail
    li t0, 71
    bne a2, t0, fail
    
pass:
    li a0, 0
    j exit
    
fail:
    li a0, 1
    
exit:
    ebreak
    j exit
