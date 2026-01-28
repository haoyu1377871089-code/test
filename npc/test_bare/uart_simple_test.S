.section .text
.globl _start
_start:
    # Simple UART test - write a single byte
    lui a5, 0x10000       # UART base 0x10000000
    li a0, 0x41           # 'A'
    sb a0, 0(a5)          # write to UART THR
    
    # Wait a few cycles
    nop
    nop
    nop
    nop
    
    # Success
    ebreak
