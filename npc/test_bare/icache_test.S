.section .text
.globl _start
_start:
    # Test I-Cache with multiple cache lines
    # Each cache line is 16 bytes = 4 instructions
    
    # Initialize test values
    li a0, 0       # counter
    li a1, 0       # sum
    
    # First cache line (0x30000000-0x3000000F): 4 instructions done
    
    # Pad to next cache line with nops
    nop
    nop
    
    # Second cache line starts here (0x30000010)
    addi a0, a0, 1      # counter++
    addi a1, a1, 1      # sum += 1
    nop
    nop
    
    # Third cache line (0x30000020)
    addi a0, a0, 1      # counter++
    addi a1, a1, 2      # sum += 2
    nop
    nop
    
    # Fourth cache line (0x30000030)
    addi a0, a0, 1      # counter++
    addi a1, a1, 3      # sum += 3
    nop
    nop
    
    # Fifth cache line (0x30000040)
    addi a0, a0, 1      # counter++
    addi a1, a1, 4      # sum += 4
    nop
    nop
    
    # Sixth cache line (0x30000050)
    addi a0, a0, 1      # counter++
    addi a1, a1, 5      # sum += 5
    nop
    nop
    
    # Seventh cache line (0x30000060)
    # Verify: counter should be 5, sum should be 1+2+3+4+5=15
    li a2, 5
    bne a0, a2, fail
    li a2, 15
    bne a1, a2, fail
    
    # Success!
    ebreak
    
fail:
    li a0, 1           # error code
    ebreak
