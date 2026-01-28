.section .text
.globl _start
_start:
    # Simple 2-iteration loop with small values
    li a0, 0              # counter
    li a1, 2              # end (just 2 iterations)
    
loop:
    nop
    addi a0, a0, 1        # counter++
    bne a0, a1, loop      # loop while counter != 2
    
    # Verify counter is 2
    li a2, 2
    bne a0, a2, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
