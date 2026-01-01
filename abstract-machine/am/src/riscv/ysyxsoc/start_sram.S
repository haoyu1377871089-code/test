/* Bootloader + Start code for SRAM execution */
/* 从 Flash 加载代码到 SRAM，然后跳转执行 */

.section entry, "ax"
.globl _start
.type _start, @function

/* UART 地址 */
.equ UART_BASE, 0x10000000
.equ UART_TX,   0x00        /* 0 * 4 */
.equ UART_DLL,  0x00        /* 0 * 4, DLAB=1 */
.equ UART_DLM,  0x04        /* 1 * 4, DLAB=1 */
.equ UART_LCR,  0x0c        /* 3 * 4 */
.equ UART_LSR,  0x14        /* 5 * 4 */

/* 初始化 UART 的宏 */
.macro UART_INIT
  li t1, UART_BASE
  /* Set DLAB=1 */
  li t2, 0x80
  sb t2, UART_LCR(t1)
  /* Set divisor = 1 */
  li t2, 0x01
  sb t2, UART_DLL(t1)
  li t2, 0x00
  sb t2, UART_DLM(t1)
  /* Clear DLAB, set 8N1 */
  li t2, 0x03
  sb t2, UART_LCR(t1)
.endm

/* 输出一个字符到 UART 的宏（等待 THRE） */
.macro UART_PUTC char
  li t1, UART_BASE
1:
  lbu t2, UART_LSR(t1)
  andi t2, t2, 0x20
  beqz t2, 1b
  li t2, \char
  sb t2, UART_TX(t1)
.endm

/* 直接输出，不等待 */
.macro UART_DIRECT char
  li t1, UART_BASE
  li t2, \char
  sb t2, UART_TX(t1)
.endm

/* 简单延迟 - 使用 a5 (x15) */
.macro DELAY count
  li a5, \count
1:
  addi a5, a5, -1
  bnez a5, 1b
.endm

_start:
  /* 初始化 s0 */
  mv s0, zero
  
  /* 设置临时栈指针（在 SRAM 末尾） */
  la sp, _stack_pointer

  /* ========== Bootloader: 拷贝代码段到 SRAM ========== */
  /* 不做任何 UART 输出，直接拷贝代码 */
  la a0, _text_load_addr   /* src: Flash 中的代码 */
  la a1, _text             /* dst: SRAM 中的代码区 */
  la a2, _text_end         /* end: SRAM 代码区结束 */
  
copy_text_loop:
  bge a1, a2, copy_text_done
  
  lw t0, 0(a0)             /* 从 Flash 读取 */
  sw t0, 0(a1)             /* 写入 SRAM */
  addi a0, a0, 4
  addi a1, a1, 4
  j copy_text_loop
  
copy_text_done:
  /* 内存屏障，确保写入完成 */
  fence.i
  
  /* ========== 跳转到 SRAM 中的 _trm_init ========== */
  la t0, _trm_init
  jr t0

.size _start, . - _start
