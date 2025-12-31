ENTRY(_start)
PHDRS { text PT_LOAD; data PT_LOAD; }

MEMORY {
  /* Flash XIP: 程序通过 XIP 方式从 Flash 执行 */
  flash : ORIGIN = 0x30000000, LENGTH = 16M
  /* SRAM: 数据段、BSS、堆栈 */
  sram  : ORIGIN = 0x0f000000, LENGTH = 8K
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
  } > sram : data

  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    . = ALIGN(4);
    _bss_end = .;
  } > sram
  
  _heap_start = .;
  
  /* Stack at the end of SRAM */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
}
