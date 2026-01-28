.section .text
.globl _start
_start:
    # Test BNE with big values
    lui a0, 0x80000       # a0 = 0x80000000
    addi a1, a0, 8        # a1 = 0x80000008
    
    # a0 != a1, so BNE should jump
    bne a0, a1, test2
    j fail                # Should not reach here
    
test2:
    # Now test equality
    addi a0, a0, 8        # a0 = 0x80000008 = a1
    
    # a0 == a1, so BNE should NOT jump
    bne a0, a1, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
