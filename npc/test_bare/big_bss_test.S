.section .text
.globl _start
_start:
    # Simulate BSS clear: clear 64 words (256 bytes) in PSRAM
    # This requires many cache line fetches and PSRAM stores
    
    lui a0, 0x80000       # a0 = 0x80000000 (PSRAM base)
    addi a1, a0, 256      # a1 = end address (256 bytes)
    
    # Main BSS clear loop
bss_clear_loop:
    sw zero, 0(a0)
    addi a0, a0, 4
    bne a0, a1, bss_clear_loop
    
    # Verify some locations are zero
    lui a0, 0x80000
    lw a2, 0(a0)
    bne a2, zero, fail
    lw a2, 128(a0)
    bne a2, zero, fail
    lw a2, 252(a0)        # last word
    bne a2, zero, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

    # Padding to make code larger (force more cache line fetches)
    .rept 256
    nop
    .endr
