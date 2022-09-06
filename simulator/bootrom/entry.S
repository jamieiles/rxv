	.align	4
	.section ".text.head", "ax"
.globl _start
_start:
	li a0, 0
	li a1, 0x80200000
	li s0, 0x84000000
	jr s0
