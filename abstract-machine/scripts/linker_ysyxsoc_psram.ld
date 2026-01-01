/* 链接脚本：代码在 PSRAM 中运行（从 Flash 加载），栈在 SRAM */
/* 适用于较大的程序，利用 PSRAM 的大容量和 SRAM 的栈访问速度 */

ENTRY(_start)

MEMORY {
  /* Flash: 存储程序镜像（LMA）和 bootloader */
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  /* SRAM: 栈区（高速访问）*/
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  /* PSRAM: 代码、数据段、BSS、堆区 */
  psram : ORIGIN = 0x80000000, LENGTH = 4M
}

SECTIONS {
  /* ========== FSBL: 在 Flash 中执行，负责搬运 SSBL 到 SRAM ========== */
  . = ORIGIN(flash);
  .fsbl : {
    KEEP(*(.fsbl))
    KEEP(*(entry))              /* 兼容旧的 entry 名称 */
    . = ALIGN(4);
  } > flash

  _fsbl_end = .;

  /* ========== SSBL: VMA 在 SRAM，LMA 在 Flash ========== */
  _ssbl_load_addr = _fsbl_end;  /* Flash 中紧跟 FSBL 之后 */

  . = ORIGIN(sram);
  .ssbl : AT(_ssbl_load_addr) {
    _ssbl_start = .;
    KEEP(*(.ssbl))
    KEEP(*(.ssbl.*))
    . = ALIGN(4);
    _ssbl_end = .;
  } > sram

  /* ========== 主程序：VMA 在 PSRAM，LMA 在 Flash ========== */
  _text_load_addr = _ssbl_load_addr + (_ssbl_end - _ssbl_start);
  _text_load_addr = ALIGN(_text_load_addr, 4);

  . = ORIGIN(psram);
  .text : AT(_text_load_addr) {
    _text = .;
    *(.text*)
    *(.rodata*)
    *(.rodata1*)
    *(.srodata*)
    *(.srodata.*)
    *(.gnu.linkonce.r*)
    . = ALIGN(4);
  } > psram
  
  _text_end = .;
  _text_size = _text_end - _text;

  /* ========== 数据段：VMA 在 PSRAM，LMA 在 Flash ========== */
  _data_load_addr = _text_load_addr + _text_size;
  
  .data : AT(_data_load_addr) {
    _data = .;
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
    _edata = .;
  } > psram
  
  _data_size = _edata - _data;

  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    . = ALIGN(4);
    _bss_end = .;
  } > psram
  
  _heap_start = .;
  _heap_end = ORIGIN(psram) + LENGTH(psram);
  
  /* 栈在 SRAM 末尾（高速访问）*/
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
}
