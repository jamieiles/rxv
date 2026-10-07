// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
//
// Runs from the DE0-CV boot ROM and touches each route through the address
// decode, storing what it reads to the framebuffer window for the test to
// check in the SDRAM, then sets all of the LEDs.  The LEDs show the step
// reached so that a hang can be located.

#define DEBUG    0xfff90000
#define FB       0xf8000000
#define DRAM     0x80001000
#define PLIC     0xfc000000
#define CLINT    0xf0000000
#define KBD      0xfffa0000
#define SDHCI    0xfffc0000
#define RESULTS  0x100

#define STEP(n)	li t0, n; sw t0, 0(s0)
#define TRAPPED  0x2aa
#define TRAP_INFO 0x80

	.section .text
	.globl _start
_start:
	li	s0, DEBUG
	li	s1, FB
	la	t0, trap
	csrw	mtvec, t0
	STEP(1)

	// The boot ROM is cacheable and writable: .data lives there.
	la	a0, rom_word
	lw	t0, 0(a0)
	addi	t0, t0, 1
	sw	t0, 0(a0)
	lw	t1, 0(a0)

	STEP(2)
	// Cached DRAM: write, clean out to the SDRAM, then refetch.
	li	a0, DRAM
	li	t2, 0x12345678
	sw	t2, 0(a0)
	li	t3, 0x9abcdef0
	sw	t3, 60(a0)
	cbo.flush	(a0)
	STEP(3)
	lw	t4, 0(a0)
	lw	t5, 60(a0)
	STEP(4)

	// Uncached framebuffer window, with a byte store.
	li	t6, 0xcafef00d
	sw	t6, 0(s1)
	STEP(0x41)
	li	a1, 0x5a
	sb	a1, 1(s1)
	STEP(0x42)
	lw	a2, 0(s1)

	STEP(5)
	// PLIC source 1 priority
	li	a3, PLIC
	li	a4, 3
	sw	a4, 4(a3)
	lw	a5, 4(a3)

	STEP(6)
	// CLINT mtime is running
	li	a6, CLINT + 0xbff8
	lw	a7, 0(a6)
	lw	s2, 0(a6)

	STEP(7)
	// PS/2 keyboard control register: enable the receive interrupt
	li	s3, KBD
	li	s4, 1
	sw	s4, 4(s3)
	lw	s5, 4(s3)

	STEP(8)
	// SDHCI host controller version and capabilities
	li	s6, SDHCI
	lw	s7, 0xfc(s6)
	lw	s8, 0x40(s6)

	STEP(9)
	sw	t1, RESULTS + 0x00(s1)
	sw	t4, RESULTS + 0x04(s1)
	sw	t5, RESULTS + 0x08(s1)
	sw	a2, RESULTS + 0x0c(s1)
	sw	a5, RESULTS + 0x10(s1)
	sw	a7, RESULTS + 0x14(s1)
	sw	s2, RESULTS + 0x18(s1)
	sw	s5, RESULTS + 0x1c(s1)
	sw	s7, RESULTS + 0x20(s1)
	sw	s8, RESULTS + 0x24(s1)

	li	t0, 0x123abc
	sw	t0, 4(s0)
	li	t0, 0x3f
	sw	t0, 8(s0)
	// Done
	li	t0, 0x3ff
	sw	t0, 0(s0)
1:
	j	1b

	// Record the cause in the framebuffer and flag it on the LEDs.
	.balign 4
trap:
	csrr	t0, mcause
	sw	t0, TRAP_INFO + 0(s1)
	csrr	t0, mepc
	sw	t0, TRAP_INFO + 4(s1)
	csrr	t0, mtval
	sw	t0, TRAP_INFO + 8(s1)
	li	t0, TRAPPED
	sw	t0, 0(s0)
1:
	j	1b

	.section .data
	.balign 64
rom_word:
	.word	0x41
