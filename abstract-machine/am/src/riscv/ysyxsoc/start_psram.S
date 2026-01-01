/*
 * 二级加载启动流程：
 * - FSBL：在 Flash 中执行，将 SSBL 从 Flash 复制到 SRAM，并跳转到 SSBL
 * - SSBL：在 SRAM 中执行，将主程序从 Flash 复制到 PSRAM，并跳转到 _trm_init
 */

/* -------------------- FSBL (Flash 执行) -------------------- */
.section .fsbl, "ax"
.globl _start
.type _start, @function

_start:
  mv s0, zero
  la sp, _stack_pointer          /* 栈放在 SRAM 尾部 */

  /* 拷贝 SSBL 到 SRAM */
  la a0, _ssbl_load_addr         /* Flash 源地址 */
  la a1, _ssbl_start             /* SRAM 目标地址 */
  la a2, _ssbl_end               /* SRAM 目标结束 */

copy_ssbl_loop:
  bge a1, a2, copy_ssbl_done
  lw t0, 0(a0)
  sw t0, 0(a1)
  addi a0, a0, 4
  addi a1, a1, 4
  j copy_ssbl_loop

copy_ssbl_done:
  fence.i
  la t0, _ssbl_entry             /* 跳转到 SRAM 中的 SSBL */
  jr t0

.size _start, . - _start

/* -------------------- SSBL (SRAM 执行) -------------------- */
.section .ssbl, "ax"
.globl _ssbl_entry
.type _ssbl_entry, @function

_ssbl_entry:
  la sp, _stack_pointer          /* 复用同一栈 */

  /* 拷贝代码段和只读数据到 PSRAM */
  la a0, _text_load_addr         /* src: Flash 中的代码+rodata */
  la a1, _text                   /* dst: PSRAM 代码区 */
  la a2, _text_end               /* end: PSRAM 代码区结束 */

copy_text_loop:
  bge a1, a2, copy_text_done
  lw t0, 0(a0)
  sw t0, 0(a1)
  addi a0, a0, 4
  addi a1, a1, 4
  j copy_text_loop

copy_text_done:
  /* 拷贝数据段到 PSRAM */
  la a0, _data_load_addr         /* src: Flash 中的数据 */
  la a1, _data                   /* dst: PSRAM 数据区 */
  la a2, _edata                  /* end: PSRAM 数据区结束 */

copy_data_loop:
  bge a1, a2, copy_data_done
  lw t0, 0(a0)
  sw t0, 0(a1)
  addi a0, a0, 4
  addi a1, a1, 4
  j copy_data_loop

copy_data_done:
  fence.i
  la t0, _trm_init               /* 跳转到 PSRAM 中的入口 */
  jr t0

.size _ssbl_entry, . - _ssbl_entry
