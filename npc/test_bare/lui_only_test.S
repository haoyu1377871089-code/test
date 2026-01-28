.section .text
.globl _start
_start:
    # Simplest LUI test
    lui a0, 0x80000       # a0 should be 0x80000000
    
    # Check high nibble (should be 8)
    # a0 >> 28 should be 8
    srli a1, a0, 28       # a1 = a0 >> 28 = 8
    
    li a2, 8              # expected value
    bne a1, a2, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
