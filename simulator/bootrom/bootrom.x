OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
	rom : ORIGIN = 0x80000000, LENGTH = 64K
	sdram : ORIGIN = 0x80000000, LENGTH = 256M
}

PHDRS {
	text PT_LOAD ;
	data PT_LOAD ;
	bss PT_LOAD ;
}

SECTIONS {
	.text 0x80000000 : AT(0x00000000) {
		*(.text.head);
		*(.text);
		*(.text.*);
	} > rom :text

	/DISCARD/ : {
		*(.comment);
		*(.debug*);
	}
}
