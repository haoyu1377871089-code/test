.section .text
.globl _start
_start:
    # Clear just 4 words (16 bytes) in PSRAM
    lui a0, 0x80000       # a0 = 0x80000000 (PSRAM base)
    addi a1, a0, 16       # a1 = 0x80000010 (end, just 4 words)
    
bss_loop:
    sw zero, 0(a0)        # Store
    addi a0, a0, 4        # Increment
    bne a0, a1, bss_loop  # Loop
    
    # Verify first word is zero
    lui a0, 0x80000
    lw a2, 0(a0)
    bne a2, zero, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
