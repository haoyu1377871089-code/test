/* 链接脚本：代码在 SRAM 中运行（从 Flash 加载）*/
/* 适用于需要快速执行的程序，如 mem-test */

ENTRY(_start)

MEMORY {
  /* Flash: 存储程序镜像（LMA）和 bootloader */
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  /* SRAM: 代码运行区（VMA）+ 栈 */
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  /* PSRAM: 数据段、BSS、堆区 */
  psram : ORIGIN = 0x80000000, LENGTH = 4M
}

SECTIONS {
  /* ========== Bootloader: 在 Flash 中执行 ========== */
  . = ORIGIN(flash);
  .boot : {
    KEEP(*(entry))     /* _start bootloader 代码，防止被 gc-sections 删除 */
    . = ALIGN(4);
  } > flash
  
  _boot_end = .;
  
  /* 计算代码段在 Flash 中的加载地址 */
  _text_load_addr = _boot_end;

  /* ========== 主程序代码段：VMA 在 SRAM，LMA 在 Flash ========== */
  . = ORIGIN(sram);
  .text : AT(_text_load_addr) {
    _text = .;
    *(.text*)
    . = ALIGN(4);
  } > sram
  
  .rodata : {
    *(.rodata*)
    . = ALIGN(4);
  } > sram
  
  _text_end = .;
  _text_size = _text_end - _text;

  /* ========== 数据段：VMA 在 PSRAM，LMA 在 Flash（紧跟代码）========== */
  _data_load_addr = _text_load_addr + _text_size;
  
  . = ORIGIN(psram);
  .data : AT(_data_load_addr) {
    _data = .;
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
    _edata = .;
  } > psram

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
  
  /* 栈在 SRAM 末尾 */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
}
