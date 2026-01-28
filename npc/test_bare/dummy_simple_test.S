.section .text
.globl _start
_start:
    # Mimic dummy test control flow:
    # 1. Initialize global_var = 42
    # 2. Load global_var
    # 3. Check if == 42
    # 4. Branch based on result
    # 5. Return from main
    # 6. Hit ebreak
    
    # Setup stack pointer
    lui sp, 0x0f002
    
    # Initialize global_var at 0x80000000 = 42
    lui a0, 0x80000       # PSRAM base
    li a1, 42             # value 42
    sw a1, 0(a0)          # store 42 to global_var
    
    # Wait for store to complete
    nop
    nop
    nop
    
    # Call main (simulated)
    jal ra, main
    
    # Should return here
    ebreak
    
main:
    # Save ra to stack
    addi sp, sp, -12
    sw ra, 8(sp)
    sw s0, 4(sp)
    
    # Load global_var into s0 (keep for later)
    lui s0, 0x80000
    
    # Load global_var
    lw a4, 0(s0)
    
    # Wait for load to complete
    nop
    nop
    nop
    
    # Check if == 42
    li a5, 42
    bne a4, a5, fail_path
    
    # Success path
    # Store 123 to global_var (like the 'G' path does)
    li a5, 123
    sw a5, 0(s0)
    
    # Restore and return
    lw ra, 8(sp)
    lw s0, 4(sp)
    li a0, 0
    addi sp, sp, 12
    ret
    
fail_path:
    # Fail - set a0 to 1 and exit directly
    li a0, 1
    ebreak
