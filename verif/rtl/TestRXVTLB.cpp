// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include "VerilogTestbench.h"
#include "VRXVTLBWrapper.h"
#include "VRXVTLBWrapper__Dpi.h"
#include "VRXVTLBWrapper_RXVTLBWrapper.h"
#include "VRXVTLBWrapper_RXVMMU.h"
#include "VRXVTLBWrapper_BusTransactor.h"
#include "RXVSim.h"
#include "SVUtils.h"

static inline uint32_t vpn0(uint32_t va)
{
    return (va >> 12) & 0x3ff;
}

static inline uint32_t vpn1(uint32_t va)
{
    return (va >> 22) & 0x3ff;
}

static const uint32_t page_mask = ~((1 << 12) - 1);

class TLBTestbench
    : public VerilogTestbench<VRXVTLBWrapper>
    , public ::testing::Test
{
public:
    TLBTestbench() : next_free_page(0x80000000), access_count(0), miss_count(0)
    {
        this->dut.valid = 0;
        pgd_base = alloc_page();
        this->dut.walk_translation_base = pgd_base >> 12;
        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024);
        sv_set_scope_name("TOP.RXVTLBWrapper.BusTransactor");
        this->dut.dpi_set_bus(bus.get());

        periodic(ClockCapture, [&] {
            if (this->dut.pmu_tlb_access)
                ++access_count;
            if (this->dut.pmu_tlb_miss)
                ++miss_count;
        });
    }

    void enable()
    {
        this->dut.enabled = 1;
    }

    uint32_t alloc_page()
    {
        auto r = next_free_page;

        next_free_page += 4096;

        return r;
    }

    void dcache_inval()
    {
        after_n_cycles(0, [&] {
            this->dut.dcache_invalidate = 1;
            after_n_cycles(1, [&] { this->dut.dcache_invalidate = 0; });
        });
        cycle(3);
        while (this->dut.dcache_busy)
            cycle();
    }

    void inval_all()
    {
        after_n_cycles(0, [&] {
            this->dut.tlb_op = VRXVTLBWrapper_RXVMMU::TLB_INV_ALL;
            after_n_cycles(1, [&] {
                this->dut.tlb_op = VRXVTLBWrapper_RXVMMU::TLB_INV_NONE;
            });
        });
        cycle(2);
    }

    void set_megapage_at(uint32_t va, uint32_t pa, uint32_t perms)
    {
        auto pte_addr = pgd_base + vpn1(va) * sizeof(uint32_t);

        bus->write(pte_addr, (pa >> 2) | perms | pte_valid, 0xf);
    }

    void set_page_at(uint32_t va, uint32_t pa, uint32_t perms)
    {
        auto pgd_addr = pgd_base + vpn1(va) * sizeof(uint32_t);
        auto pgd = bus->read(pgd_addr);

        if (!(pgd & pte_valid)) {
            auto p = alloc_page();

            bus->write(pgd_addr, (p >> 2) | pte_valid, 0xf);
        }

        auto pte_addr =
            ((bus->read(pgd_addr) & ~0x1) << 2) + vpn0(va) * sizeof(uint32_t);
        bus->write(pte_addr, (pa >> 2) | perms | pte_valid, 0xf);
    }

    struct Translation {
        uint32_t pa;
        bool dirty;
        bool accessed;
        bool page_global;
        bool user;
        bool exec;
        bool write;
        bool read;
        bool valid;
        uint32_t asid;
    };

    Translation translate(uint32_t va)
    {
        after_n_cycles(0, [&] {
            this->dut.va = va >> 12;
            this->dut.valid = 1;
            after_n_cycles(1, [&] {
                this->dut.valid = 0;
                this->dut.grant = 1;
            });
        });
        cycle(2);

        int i = 1024;
        while (this->dut.busy && i-- > 0)
            cycle();
        after_n_cycles(0, [&] { this->dut.grant = 0; });

        Translation t;
        t.pa = this->dut.RXVMMU->translation_pa(this->dut.translation) << 12;
        t.dirty = this->dut.RXVMMU->translation_dirty(this->dut.translation);
        t.accessed =
            this->dut.RXVMMU->translation_accessed(this->dut.translation);
        t.page_global =
            this->dut.RXVMMU->translation_page_global(this->dut.translation);
        t.user = this->dut.RXVMMU->translation_user(this->dut.translation);
        t.exec = this->dut.RXVMMU->translation_exec(this->dut.translation);
        t.write = this->dut.RXVMMU->translation_write(this->dut.translation);
        t.read = this->dut.RXVMMU->translation_read(this->dut.translation);
        t.valid = this->dut.RXVMMU->translation_valid(this->dut.translation);
        t.asid = this->dut.RXVMMU->translation_asid(this->dut.translation);

        return t;
    }

    std::shared_ptr<MemoryBus> bus;
    uint32_t next_free_page;
    uint32_t pgd_base;
    uint64_t access_count;
    uint64_t miss_count;
};

bool operator==(const TLBTestbench::Translation &lhs,
                const TLBTestbench::Translation &rhs)
{
    return lhs.pa == rhs.pa && lhs.dirty == rhs.dirty &&
           lhs.accessed == rhs.accessed && lhs.page_global == rhs.page_global &&
           lhs.user == rhs.user && lhs.exec == rhs.exec &&
           lhs.write == rhs.write && lhs.read == rhs.read &&
           lhs.valid == rhs.valid && lhs.asid == rhs.asid;
}

TEST_F(TLBTestbench, Page)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = translate(0xc0004000);
    auto t2 = translate(0xc0004000);

    EXPECT_EQ(t1, t2);
    EXPECT_EQ(2, access_count);
    EXPECT_EQ(1, miss_count);
}

TEST_F(TLBTestbench, MegaPage)
{
    enable();

    set_megapage_at(0xc0000000, 0x80000000, pte_read | pte_write | pte_user);

    auto t1 = translate(0xc0024000);

    EXPECT_EQ(t1.pa, 0x80024000);
}

TEST_F(TLBTestbench, MegaPageBoundary)
{
    enable();

    set_megapage_at(0xc0000000, 0x80000000, pte_read | pte_write | pte_user);

    const auto mb4 = 4 * 1024 * 1024;
    auto t1 = translate(0xc0000000 + mb4 - 4);

    EXPECT_EQ(t1.pa, (0x80000000 + mb4 - 4) & page_mask);
    EXPECT_TRUE(t1.valid);

    t1 = translate(0xc0000000 + mb4);

    EXPECT_FALSE(t1.valid);
}

TEST_F(TLBTestbench, CachedTranslation)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = translate(0xc0004000);

    set_page_at(0xc0004000, 0x80000000, pte_read);
    dcache_inval();
    auto t2 = translate(0xc0004000);

    EXPECT_EQ(t1, t2);

    EXPECT_EQ(2, access_count);
    EXPECT_EQ(1, miss_count);
}

TEST_F(TLBTestbench, ASIDAlias)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    this->dut.active_asid = 1;
    translate(0xc0004000);

    this->dut.active_asid = 2;
    set_page_at(0xc0004000, 0x80000000, pte_read);
    dcache_inval();
    translate(0xc0004000);

    this->dut.active_asid = 1;
    auto t1 = translate(0xc0004000);
    this->dut.active_asid = 2;
    auto t2 = translate(0xc0004000);

    EXPECT_EQ(t1.pa, 0x80012000);
    EXPECT_EQ(t2.pa, 0x80000000);
}

TEST_F(TLBTestbench, GlobalMappings)
{
    enable();

    set_page_at(0xc0004000, 0x80012000,
                pte_read | pte_write | pte_user | pte_global);

    this->dut.active_asid = 1;
    auto t1 = translate(0xc0004000);

    this->dut.active_asid = 2;
    set_page_at(0xc0004000, 0, 0);
    dcache_inval();

    auto t2 = translate(0xc0004000);

    EXPECT_EQ(t1, t2);
}

TEST_F(TLBTestbench, PageNotMapped)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = translate(0x40000000);
    EXPECT_FALSE(t1.valid);
    auto t2 = translate(0xc0004000);
    EXPECT_TRUE(t2.valid);
    EXPECT_EQ(t2.pa, 0x80012000);

    EXPECT_EQ(2, access_count);
    EXPECT_EQ(2, miss_count);
}

TEST_F(TLBTestbench, ReservedBits)
{
    enable();

    set_page_at(0xc0004000, 0x80012000,
                pte_read | pte_write | pte_user | (3 << 8));

    auto t = translate(0xc0004000);
    EXPECT_TRUE(t.valid);
}

TEST_F(TLBTestbench, Bypass)
{
    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);
    auto t = translate(0xc0004000);
    EXPECT_TRUE(t.valid);
    EXPECT_EQ(0xc0004000, t.pa);
}

TEST_F(TLBTestbench, NoGrantStalls)
{
    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);
    enable();

    after_n_cycles(0, [&] {
        this->dut.va = 0xc0004000 >> 12;
        this->dut.valid = 1;
        after_n_cycles(1, [&] { this->dut.valid = 0; });
    });
    cycle(2);

    for (int i = 0; i < 10; ++i) {
        EXPECT_TRUE(this->dut.walk_valid_req);
        EXPECT_TRUE(this->dut.busy);
        cycle();
    }
    after_n_cycles(0, [&] { this->dut.grant = 1; });

    int i = 1024;
    while (this->dut.busy && i-- > 0)
        cycle();
    EXPECT_FALSE(this->dut.busy);
}

TEST_F(TLBTestbench, ValidClearsLast)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    translate(0xc0004000);
    after_n_cycles(0, [&] {
        this->dut.va = 0;
        this->dut.valid = 1;
        after_n_cycles(1, [&] { this->dut.valid = 0; });
    });
    cycle(2);

    EXPECT_EQ(this->dut.translation, 0);
    EXPECT_TRUE(this->dut.busy);
}