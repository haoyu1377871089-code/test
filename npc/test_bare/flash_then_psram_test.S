.section .text
.globl _start
_start:
    # Test the exact sequence that fails:
    # 1. Load from Flash
    # 2. Store to PSRAM (using loaded value)
    
    # Setup PSRAM address
    lui a4, 0x80000       # a4 = 0x80000000 (PSRAM)
    
    nop
    nop
    nop
    
    # Setup Flash address
    la a5, flash_data     # a5 = address of data in Flash
    
    nop
    nop
    nop
    
    # Load from Flash
    lw a2, 0(a5)          # a2 = value from Flash (should be 42)
    
    # Extra NOPs to ensure load completes
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    
    # Store to PSRAM - THIS MIGHT CAUSE THE ISSUE!
    sw a2, 0(a4)          # Store loaded value to PSRAM
    
    # Extra NOPs
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    
    # Load back to verify
    lw a3, 0(a4)
    
    nop
    nop
    nop
    nop
    nop
    
    # Check
    li t0, 42
    bne a3, t0, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

.align 4
flash_data:
    .word 42
