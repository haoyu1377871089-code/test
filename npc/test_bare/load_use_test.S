.section .text
.globl _start
_start:
    # Test load-use hazard with SRAM (faster than PSRAM)
    # Stack pointer (sp) is typically in SRAM
    
    # Use SRAM address
    lui a0, 0x0f000       # SRAM is at 0x0F000000
    li a1, 0x42           # test value
    
    sw a1, 0(a0)          # store to SRAM
    lw a2, 0(a0)          # load from SRAM
    # load-use hazard: next instruction uses a2
    addi a2, a2, 1        # a2 should be 0x43
    
    li a3, 0x43
    bne a2, a3, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak
