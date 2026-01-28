.section .text
.globl _start
_start:
    # Test PSRAM store operations
    # PSRAM is at 0x80000000
    
    # Setup: load PSRAM base address
    lui a0, 0x80000     # a0 = 0x80000000 (PSRAM base)
    
    # Test 1: Single word store
    li a1, 0x12345678
    sw a1, 0(a0)        # Store to PSRAM
    
    # Test 2: Read back
    lw a2, 0(a0)        # Load from PSRAM
    bne a1, a2, fail
    
    # Test 3: Multiple stores (simulate BSS clear)
    sw zero, 4(a0)      # Clear word 1
    sw zero, 8(a0)      # Clear word 2
    sw zero, 12(a0)     # Clear word 3
    sw zero, 16(a0)     # Clear word 4
    
    # Test 4: Verify all cleared
    lw a2, 4(a0)
    bne a2, zero, fail
    lw a2, 8(a0)
    bne a2, zero, fail
    lw a2, 12(a0)
    bne a2, zero, fail
    lw a2, 16(a0)
    bne a2, zero, fail
    
    # Success
    ebreak
    
fail:
    li a0, 1            # error code
    ebreak
