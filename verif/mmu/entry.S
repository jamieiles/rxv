// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
    .section .text.init
    .globl _start
_start:
    la sp, _stack_top
    la t0, trap_entry
    csrw mtvec, t0
    la t0, _bss_start
    la t1, _bss_end
1:  bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:  call m_main
    csrw 0x800, a0
3:  j 3b

    .align 4
trap_entry:
    csrw mscratch, sp
    la sp, _trap_stack_top
    addi sp, sp, -64
    sw ra, 0(sp)
    sw a0, 4(sp)
    sw a1, 8(sp)
    sw a2, 12(sp)
    sw a3, 16(sp)
    sw a4, 20(sp)
    sw a5, 24(sp)
    sw t0, 28(sp)
    sw t1, 32(sp)
    sw t2, 36(sp)
    sw a6, 40(sp)
    sw a7, 44(sp)
    sw t3, 48(sp)
    sw t4, 52(sp)
    sw t5, 56(sp)
    sw t6, 60(sp)
    call m_trap
    lw ra, 0(sp)
    lw a0, 4(sp)
    lw a1, 8(sp)
    lw a2, 12(sp)
    lw a3, 16(sp)
    lw a4, 20(sp)
    lw a5, 24(sp)
    lw t0, 28(sp)
    lw t1, 32(sp)
    lw t2, 36(sp)
    lw a6, 40(sp)
    lw a7, 44(sp)
    lw t3, 48(sp)
    lw t4, 52(sp)
    lw t5, 56(sp)
    lw t6, 60(sp)
    csrr sp, mscratch
    mret
