// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
//
// Loaded as OPENSBI.BIN by the DE0-CV boot ROM test: checks the arguments
// the boot ROM passes (hart 0, the DTB address) and reports on the LEDs.

#define DEBUG	0xfff90000
#define DTB	0x80200000
#define PASS	0x155
#define FAIL	0x0aa

	.section .text
	.globl _start
_start:
	li	t0, DEBUG
	li	t1, DTB
	bne	a1, t1, bad
	bnez	a0, bad
	li	t1, PASS
	sw	t1, 0(t0)
1:
	j	1b
bad:
	li	t1, FAIL
	sw	t1, 0(t0)
2:
	j	2b
