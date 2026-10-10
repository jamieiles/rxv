// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
//
// Sv32 MMU and TLB test.  Machine mode builds page tables, mapping 48 4K
// test pages to a permutation of physical pages and the RAM and UART with
// global megapages, then runs the tests in supervisor mode:
//
//   - sweeps of working sets smaller and larger than the TLB, reporting the
//     steady state DTLB misses from the PMU when running on the RTL
//   - remapping with address and address+ASID sfence.vma
//   - switching ASID without a flush and flushing a single ASID
//   - page faults for a misaligned megapage, a reserved W-only PTE, a
//     non-leaf last level PTE and a PTE without A set
//
// Prints "MMU TEST PASSED" and exits through the simulator exit CSR.
#include <stdint.h>
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_G 0x20
#define PTE_A 0x40
#define PTE_D 0x80
#define ROOT1 ((volatile uint32_t *)0x80100000)
#define L0_1  ((volatile uint32_t *)0x80101000)
#define ROOT2 ((volatile uint32_t *)0x80102000)
#define L0_2  ((volatile uint32_t *)0x80103000)
#define DATA_PA 0x80200000u
#define TEST_VA 0x40000000u
#define NPAGES 48
#define CSR_READ(c) ({ uint32_t v; __asm__ volatile("csrr %0, " #c : "=r"(v)); v; })
#define CSR_WRITE(c, v) __asm__ volatile("csrw " #c ", %0" ::"r"(v))
static inline void sfence_all(void) { __asm__ volatile("sfence.vma" ::: "memory"); }
static inline void sfence_va(uint32_t va) { __asm__ volatile("sfence.vma %0, zero" ::"r"(va) : "memory"); }
static inline void sfence_va_asid(uint32_t va, uint32_t asid) { __asm__ volatile("sfence.vma %0, %1" ::"r"(va), "r"(asid) : "memory"); }
static inline void sfence_asid(uint32_t asid) { __asm__ volatile("sfence.vma zero, %0" ::"r"(asid) : "memory"); }

static void putc_(char c) { *(volatile uint8_t *)0xffff1000 = c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }
static void puthex(uint32_t v) { for (int i = 28; i >= 0; i -= 4) putc_("0123456789abcdef"[(v >> i) & 15]); }
static void putdec(uint32_t v) { char b[12]; int n = 0; do { b[n++] = '0' + v % 10; v /= 10; } while (v); while (n) putc_(b[--n]); }

static int is_rtl;
static int failures;
static volatile int expect_fault;
static volatile uint32_t fault_cause;

static uint32_t perm(uint32_t i) { return (i * 37 + 11) % 64; }
static uint32_t page_value(uint32_t ppage) { return 0xc0de0000u ^ (ppage * 0x01010101u); }
static uint32_t pte_for(uint32_t pa, uint32_t flags) { return ((pa >> 12) << 10) | flags; }

static void check(const char *what, uint32_t got, uint32_t want)
{
    if (got != want) {
        ++failures;
        puts_("FAIL "); puts_(what); puts_(" got "); puthex(got); puts_(" want "); puthex(want); puts_("\n");
    }
}

static uint32_t dtlb_misses(void) { return is_rtl ? CSR_READ(0xc03) : 0; }
static uint32_t dtlb_reads(void) { return is_rtl ? CSR_READ(0xc04) : 0; }

void m_trap(void)
{
    uint32_t cause = CSR_READ(mcause);
    if (cause == 9) {  /* ecall from S: done */
        puts_(failures ? "MMU TEST FAILED\n" : "MMU TEST PASSED\n");
        __asm__ volatile("csrw 0x800, %0" ::"r"(failures));
        for (;;) ;
    }
    if (expect_fault) {
        fault_cause = cause;
        expect_fault = 0;
        CSR_WRITE(mepc, CSR_READ(mepc) + 4);
        return;
    }
    puts_("unexpected trap mcause="); puthex(cause); puts_(" mepc="); puthex(CSR_READ(mepc));
    puts_(" mtval="); puthex(CSR_READ(mtval)); puts_("\n");
    __asm__ volatile("csrw 0x800, %0" ::"r"(0xdead));
    for (;;) ;
}

static uint32_t try_load(uint32_t va)
{
    fault_cause = 0; expect_fault = 1;
    uint32_t v = *(volatile uint32_t *)va;
    (void)v;
    if (expect_fault) { expect_fault = 0; return 0; }
    return fault_cause;
}

static uint32_t try_store(uint32_t va)
{
    fault_cause = 0; expect_fault = 1;
    *(volatile uint32_t *)va = 0x1234;
    if (expect_fault) { expect_fault = 0; return 0; }
    return fault_cause;
}

static void s_main(void)
{
    puts_("S-mode with Sv32\n");

    /* T1: working set sweeps */
    static const int ws_list[] = {4, 6, 7, 8, 9, 12, 16, 48};
    for (unsigned w = 0; w < sizeof(ws_list) / sizeof(ws_list[0]); ++w) {
        int ws = ws_list[w];
        uint32_t m0 = 0, r0 = 0;
        for (int pass = 0; pass < 10; ++pass) {
            if (pass == 2) { m0 = dtlb_misses(); r0 = dtlb_reads(); }
            for (int i = 0; i < ws; ++i)
                check("sweep", *(volatile uint32_t *)(TEST_VA + i * 4096), page_value(perm(i)));
        }
        uint32_t m = dtlb_misses() - m0, r = dtlb_reads() - r0;
        puts_("ws="); putdec(ws); puts_(" steady state dtlb misses/8 passes="); putdec(m);
        puts_(" (reads "); putdec(r); puts_(")\n");
    }

    /* T2: remap page 0 with address only and address+asid sfence */
    uint32_t orig = L0_1[0];
    check("t2 before", *(volatile uint32_t *)TEST_VA, page_value(perm(0)));
    L0_1[0] = pte_for(DATA_PA + 60 * 4096, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);
    sfence_va(TEST_VA);
    check("t2 remap va", *(volatile uint32_t *)TEST_VA, page_value(60));
    L0_1[0] = orig;
    sfence_va_asid(TEST_VA, 1);
    check("t2 restore va+asid", *(volatile uint32_t *)TEST_VA, page_value(perm(0)));

    /* T3: switch ASID without a flush, distinct translations per ASID */
    uint32_t satp1 = CSR_READ(satp);
    uint32_t satp2 = (1u << 31) | (2u << 22) | (0x80102000u >> 12);
    for (int i = 0; i < 4; ++i)
        check("t3 asid1 warm", *(volatile uint32_t *)(TEST_VA + i * 4096), page_value(perm(i)));
    CSR_WRITE(satp, satp2);
    for (int i = 0; i < 4; ++i)
        check("t3 asid2", *(volatile uint32_t *)(TEST_VA + i * 4096), page_value(63 - i));
    CSR_WRITE(satp, satp1);
    for (int i = 0; i < 4; ++i)
        check("t3 asid1 again", *(volatile uint32_t *)(TEST_VA + i * 4096), page_value(perm(i)));
    sfence_asid(2);
    CSR_WRITE(satp, satp2);
    check("t3 asid2 after flush", *(volatile uint32_t *)TEST_VA, page_value(63));
    /* change ASID 2's mapping, flush only ASID 1, then ASID 2 */
    L0_2[0] = pte_for(DATA_PA + 59 * 4096, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);
    sfence_asid(2);
    check("t3 asid2 remap", *(volatile uint32_t *)TEST_VA, page_value(59));
    CSR_WRITE(satp, satp1);

    /* T5: faults */
    check("t5 misaligned megapage load", try_load(0x40400000u), 13);
    check("t5 level0 non-leaf load", try_load(TEST_VA + 62 * 4096), 13);
    check("t5 W-only (reserved) store", try_store(TEST_VA + 61 * 4096), 15);
    check("t5 no-A load", try_load(TEST_VA + 60 * 4096), 13);

    /* T6: flush everything and sweep again */
    sfence_all();
    for (int i = 0; i < NPAGES; ++i)
        check("t6 sweep", *(volatile uint32_t *)(TEST_VA + i * 4096), page_value(perm(i)));

    __asm__ volatile("ecall");
}

int m_main(void)
{
    is_rtl = CSR_READ(mvendorid) != 0;
    for (uint32_t p = 0; p < 64; ++p)
        *(volatile uint32_t *)(DATA_PA + p * 4096) = page_value(p);
    for (int i = 0; i < 1024; ++i) { ROOT1[i] = 0; L0_1[i] = 0; ROOT2[i] = 0; L0_2[i] = 0; }
    for (uint32_t j = 0; j < 4; ++j) {
        uint32_t e = pte_for((0x200 + j) << 22, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D | PTE_G);
        ROOT1[0x200 + j] = e; ROOT2[0x200 + j] = e;
    }
    ROOT1[0x3ff] = ROOT2[0x3ff] = pte_for(0xffc00000u, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D | PTE_G);
    ROOT1[0x100] = pte_for(0x80101000u, PTE_V);
    ROOT2[0x100] = pte_for(0x80103000u, PTE_V);
    ROOT1[0x101] = pte_for(DATA_PA + 4096, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D); /* misaligned megapage */
    for (uint32_t i = 0; i < NPAGES; ++i)
        L0_1[i] = pte_for(DATA_PA + perm(i) * 4096, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);
    L0_1[60] = pte_for(DATA_PA, PTE_V | PTE_R | PTE_W | PTE_D);           /* A clear */
    L0_1[61] = pte_for(DATA_PA, PTE_V | PTE_W | PTE_A | PTE_D);           /* W-only reserved */
    L0_1[62] = pte_for(0x80101000u, PTE_V);                               /* non-leaf at level 0 */
    for (uint32_t i = 0; i < 4; ++i)
        L0_2[i] = pte_for(DATA_PA + (63 - i) * 4096, PTE_V | PTE_R | PTE_W | PTE_A | PTE_D);

    /* PMP: allow everything for S-mode */
    CSR_WRITE(pmpaddr0, 0xffffffffu);
    CSR_WRITE(pmpcfg0, 0x1f);
    if (is_rtl) {
        CSR_WRITE(0x323, 14); /* mhpmevent3 = DTLB_READ_MISS */
        CSR_WRITE(0x324, 13); /* mhpmevent4 = DTLB_READ */
        CSR_WRITE(mcounteren, 0xffffffffu);
        CSR_WRITE(0x320, 0);  /* mcountinhibit */
    }
    CSR_WRITE(satp, (1u << 31) | (1u << 22) | (0x80100000u >> 12));
    uint32_t ms = CSR_READ(mstatus);
    ms = (ms & ~(3u << 11)) | (1u << 11); /* MPP = S */
    CSR_WRITE(mstatus, ms);
    CSR_WRITE(mepc, (uint32_t)s_main);
    __asm__ volatile("mret");
    return 1;
}
