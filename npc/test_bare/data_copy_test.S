.section .text
.globl _start
_start:
    # Test data copying from Flash to PSRAM
    # Similar to _trm_init data section copy
    
    # Source: Flash address (in .text section)
    la a5, data_src      # source address in Flash (0x30000xxx)
    
    # Destination: PSRAM address
    lui a4, 0x80000      # dest = 0x80000000
    
    # Copy 1 word
    lw a2, 0(a5)         # load from Flash
    
    # NOPs to avoid hazards
    nop
    nop
    nop
    
    sw a2, 0(a4)         # store to PSRAM
    
    # Wait for store
    nop
    nop
    nop
    
    # Now verify
    lw a3, 0(a4)         # load back from PSRAM
    
    nop
    nop
    nop
    
    # Check if matches original
    li t0, 42            # expected value
    bne a3, t0, fail
    
    # Also check if source was correct
    bne a2, t0, fail_src
    
    # Success
    ebreak
    
fail:
    li a0, 1
    ebreak

fail_src:
    li a0, 2
    ebreak

.align 4
data_src:
    .word 42             # This should be 42 when loaded
