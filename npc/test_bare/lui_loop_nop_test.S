.section .text
.globl _start
_start:
    # Same as lui_loop_test but with nops before ebreak
    lui a0, 0x80000       # a0 = 0x80000000
    addi a1, a0, 8        # a1 = 0x80000008
    
loop:
    nop
    addi a0, a0, 4
    bne a0, a1, loop
    
    # Add extra nops before ebreak to help pipeline flush
    nop
    nop
    nop
    nop
    
    # Success
    ebreak
