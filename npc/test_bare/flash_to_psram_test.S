.section .text
.globl _start
_start:
    # Test: Load from Flash, store to PSRAM
    # With extra NOPs to avoid any hazards
    
    # Step 1: Load address of data in Flash
    la a5, data_src      # a5 = address of data in Flash
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 2: Load destination address (PSRAM)
    lui a4, 0x80000      # a4 = 0x80000000
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 3: Load value from Flash
    lw a2, 0(a5)         # a2 = value (should be 42)
    
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
    
    # Step 4: Store to PSRAM
    sw a2, 0(a4)         # Store to PSRAM
    
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
    
    # Step 5: Load back from PSRAM
    lw a3, 0(a4)         # a3 = loaded value
    
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
    
    # Step 6: Verify
    li t0, 42
    bne a3, t0, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

.align 4
data_src:
    .word 42
