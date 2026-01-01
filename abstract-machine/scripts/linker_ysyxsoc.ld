ENTRY(_start)
PHDRS { text PT_LOAD; data PT_LOAD; }

MEMORY {
  /* Flash XIP: 程序通过 XIP 方式从 Flash 执行 */
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  /* SRAM: 仅用于栈 */
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
  /* PSRAM: 数据段、BSS、堆区 */
  psram : ORIGIN = 0x80000000, LENGTH = 4M
}

SECTIONS {
  . = ORIGIN(flash);
  .text : {
    *(entry)
    *(.text*)
  } > flash : text
  etext = .;
  _etext = .;
  .rodata : {
    *(.rodata*)
  } > flash : text

  . = ALIGN(4);
  _data_load_addr = .;

  .data : AT(_data_load_addr) {
    _data = .;
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
    _edata = .;
  } > psram : data

  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    . = ALIGN(4);
    _bss_end = .;
  } > psram
  
  _heap_start = .;
  /* 堆区在PSRAM中，可使用剩余空间 */
  _heap_end = ORIGIN(psram) + LENGTH(psram);
  
  /* Stack at the end of SRAM */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
}
