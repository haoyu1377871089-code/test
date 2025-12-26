ENTRY(_start)
PHDRS { text PT_LOAD; data PT_LOAD; }

MEMORY {
  mrom : ORIGIN = 0x20000000, LENGTH = 4K
  sram : ORIGIN = 0x0f000000, LENGTH = 8K
}

SECTIONS {
  . = ORIGIN(mrom);
  .text : {
    *(entry)
    *(.text*)
  } > mrom : text
  etext = .;
  _etext = .;
  .rodata : {
    *(.rodata*)
  } > mrom : text

  . = ALIGN(4);
  _data_load_addr = .;

  .data : AT(_data_load_addr) {
    _data = .;
    *(.data*)
    *(.sdata*)
    _edata = .;
  } > sram : data

  .bss : {
_bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    _bss_end = .;
  } > sram
  
  _heap_start = .;
  
  /* Stack at the end of SRAM */
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
}
