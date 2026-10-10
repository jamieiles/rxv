OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text : { *(.text.init) *(.text .text.*) }
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
  .data : { *(.data .data.* .sdata .sdata.*) }
  . = ALIGN(4);
  _bss_start = .;
  .bss : { *(.sbss .sbss.* .bss .bss.* COMMON) }
  . = ALIGN(4);
  _bss_end = .;
  . = ALIGN(16) + 0x4000;
  _trap_stack_top = .;
  . = . + 0x10000;
  _stack_top = .;
}
