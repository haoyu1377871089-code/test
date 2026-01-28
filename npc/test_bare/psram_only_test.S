.section .text
.globl _start
_start:
    # Test: Only PSRAM operations - no Flash data load
    # Step 1: Store value to PSRAM
    lui a0, 0x80000       # PSRAM base 0x80000000
    li a1, 42             # test value
    sw a1, 0(a0)          # store to PSRAM
    
    # Wait
    nop
    nop
    nop
    nop
    nop
    
    # Step 2: Store another value to different offset
    li a1, 123
    sw a1, 4(a0)          # store to PSRAM+4
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 3: Load back first value
    lw a2, 0(a0)          # load from PSRAM
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 4: Load back second value
    lw a3, 4(a0)          # load from PSRAM+4
    
    nop
    nop
    nop
    nop
    nop
    
    # Step 5: Verify first value
    li t0, 42
    bne a2, t0, fail
    
    # Step 6: Verify second value
    li t0, 123
    bne a3, t0, fail
    
    # Success!
    ebreak
    
fail:
    li a0, 1
    ebreak
