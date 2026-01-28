.section .text
.globl _start
_start:
    # Simple PSRAM test without load-use hazard
    lui a0, 0x80000       # PSRAM base 0x80000000
    li a1, 0xAB           # test value
    
    sw a1, 0(a0)          # store to PSRAM (instruction 3)
    
    # Insert NOPs to avoid load-use hazard
    nop
    nop
    nop
    
    lw a2, 0(a0)          # load from PSRAM (instruction 7)
    
    # More NOPs to ensure load completes
    nop
    nop
    nop
    
    # Now check value (instruction 11)
    li a3, 0xAB
    bne a2, a3, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
