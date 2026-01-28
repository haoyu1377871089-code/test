.section .text
.globl _start
_start:
    # Test: LSU load from Flash ONLY - no PSRAM
    # This isolates the Flash LSU load issue
    
    # Step 1: Load address of data in Flash
    la a0, flash_data     # a0 = address of data in Flash (0x30000xxx)
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 2: Load value from Flash via LSU (this might fail!)
    lw a1, 0(a0)          # a1 = value from Flash
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 3: Check value
    li t0, 42
    bne a1, t0, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

.align 4
flash_data:
    .word 42
