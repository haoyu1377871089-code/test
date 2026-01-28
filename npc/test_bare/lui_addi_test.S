.section .text
.globl _start
_start:
    # Test LUI followed by ADDI (RAW hazard on a0)
    lui a0, 0x80000       # a0 = 0x80000000
    addi a1, a0, 8        # a1 = a0 + 8 = 0x80000008 (RAW hazard!)
    
    # Check a1 value
    # a1 >> 28 should be 8 (high nibble of 0x80000008 is 8)
    srli a2, a1, 28       # a2 = a1 >> 28 = 8
    li a3, 8
    bne a2, a3, fail
    
    # Check lower bits: (a1 & 0xF) should be 8
    andi a2, a1, 0xF      # a2 = a1 & 0xF = 8
    bne a2, a3, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
