ENTRY(_start)

MEMORY {
  sram : ORIGIN = 0x0f000800, LENGTH = 2K
}

SECTIONS {
  . = ORIGIN(sram);
  .text : {
    *(.text*)
  } > sram
  
  .rodata : {
    *(.rodata*)
  } > sram
  
  .data : {
    *(.data*)
    *(.sdata*)
  } > sram
  
  .bss : {
    *(.bss*)
    *(.sbss*)
  } > sram
}
