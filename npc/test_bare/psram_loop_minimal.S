.section .text
.globl _start
_start:
    # Minimal PSRAM loop test: store to 2 addresses
    lui a0, 0x80000       # PSRAM base
    addi a1, a0, 8        # end = base + 8 (just 2 words)
    
loop:
    sw zero, 0(a0)
    nop                   # delay
    nop
    addi a0, a0, 4
    bne a0, a1, loop
    
    # Success
    ebreak
