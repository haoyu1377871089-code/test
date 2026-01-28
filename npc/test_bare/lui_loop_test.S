.section .text
.globl _start
_start:
    # Test lui + addi + loop (no memory access)
    lui a0, 0x80000       # a0 = 0x80000000
    addi a1, a0, 8        # a1 = 0x80000008
    
    # Just a simple 2-iteration loop with no store
loop:
    nop
    addi a0, a0, 4
    bne a0, a1, loop
    
    # Success
    ebreak
