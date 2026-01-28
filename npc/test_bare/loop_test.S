.section .text
.globl _start
_start:
    # Simple counted loop test
    li a0, 0          # counter
    li a1, 10         # loop count (small)
    li a2, 0          # sum
    
loop:
    addi a2, a2, 1    # sum++
    addi a0, a0, 1    # counter++
    bne a0, a1, loop  # if counter != 10, continue
    
    # Verify: a0 should be 10, a2 should be 10
    li a3, 10
    bne a0, a3, fail
    bne a2, a3, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
