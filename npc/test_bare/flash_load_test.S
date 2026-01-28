.section .text
.globl _start
_start:
    # Test loading from Flash only - no PSRAM writes
    
    # Load from Flash (data in .text section)
    la a5, data_src      # source address in Flash
    
    nop
    nop
    nop
    
    lw a2, 0(a5)         # load from Flash
    
    nop
    nop
    nop
    
    # Check the loaded value
    li t0, 42
    bne a2, t0, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

.align 4
data_src:
    .word 42
