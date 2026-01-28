.section .text
.globl _start
_start:
    # Minimal test: Load immediate, store to PSRAM - should work
    lui a0, 0x80000       # PSRAM base
    li a1, 42             # test value
    sw a1, 0(a0)          # store to PSRAM
    
    nop
    nop
    nop
    nop
    nop
    
    # Now try: Load from Flash, store to PSRAM - might fail?
    la a2, flash_data     # Flash address
    
    nop
    nop
    nop
    
    lw a3, 0(a2)          # load from Flash (0x30000xxx)
    
    nop
    nop
    nop
    nop
    nop
    
    sw a3, 4(a0)          # store to PSRAM at offset 4
    
    # If we reach here, check values
    nop
    nop
    nop
    nop
    nop
    
    lw a4, 4(a0)          # load back
    
    nop
    nop
    nop
    
    li a5, 123
    bne a4, a5, fail
    
    # Also verify first store worked
    lw a4, 0(a0)
    nop
    nop
    nop
    li a5, 42
    bne a4, a5, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

.align 4
flash_data:
    .word 123
