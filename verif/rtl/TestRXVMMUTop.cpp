#include "VerilogTestbench.h"
#include "VRXVMMUTopWrapper.h"
#include "VRXVMMUTopWrapper_RXVMMUTopWrapper.h"
#include "VRXVMMUTopWrapper_RXVMMU.h"
#include "VRXVMMUTopWrapper_BusTransactor.h"
#include "RXVSim.h"

static inline uint32_t vpn0(uint32_t va)
{
    return (va >> 12) & 0x3ff;
}

static inline uint32_t vpn1(uint32_t va)
{
    return (va >> 22) & 0x3ff;
}

class MMUTestbench
    : public VerilogTestbench<VRXVMMUTopWrapper>
    , public ::testing::Test
{
public:
    MMUTestbench() : next_free_page(0x80000000)
    {
        this->dut.d_valid = 0;
        pgd_base = alloc_page();
        this->dut.translation_base = pgd_base >> 12;
        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024);
        this->dut.RXVMMUTopWrapper->BusTransactor->set_bus(bus);
    }

    void enable()
    {
        this->dut.d_enabled = 1;
        this->dut.i_enabled = 1;
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
            this->dut.tlb_op = VRXVMMUTopWrapper_RXVMMU::TLB_INV_ALL;
            after_n_cycles(1, [&] {
                this->dut.tlb_op = VRXVMMUTopWrapper_RXVMMU::TLB_INV_NONE;
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

    Translation d_translate(uint32_t va)
    {
        after_n_cycles(0, [&] {
            this->dut.d_va = va >> 12;
            this->dut.d_valid = 1;
            after_n_cycles(1, [&] { this->dut.d_valid = 0; });
        });
        cycle(2);

        int i = 1024;
        while (this->dut.d_busy && i-- > 0)
            cycle();

        Translation t;
        t.pa = this->dut.RXVMMU->translation_pa(this->dut.d_translation) << 12;
        t.dirty = this->dut.RXVMMU->translation_dirty(this->dut.d_translation);
        t.accessed =
            this->dut.RXVMMU->translation_accessed(this->dut.d_translation);
        t.page_global =
            this->dut.RXVMMU->translation_page_global(this->dut.d_translation);
        t.user = this->dut.RXVMMU->translation_user(this->dut.d_translation);
        t.exec = this->dut.RXVMMU->translation_exec(this->dut.d_translation);
        t.write = this->dut.RXVMMU->translation_write(this->dut.d_translation);
        t.read = this->dut.RXVMMU->translation_read(this->dut.d_translation);
        t.valid = this->dut.RXVMMU->translation_valid(this->dut.d_translation);
        t.asid = this->dut.RXVMMU->translation_asid(this->dut.d_translation);

        return t;
    }

    Translation i_translate(uint32_t va)
    {
        after_n_cycles(0, [&] {
            this->dut.i_va = va >> 12;
            this->dut.i_valid = 1;
            after_n_cycles(1, [&] { this->dut.i_valid = 0; });
        });
        cycle(2);

        int i = 1024;
        while (this->dut.i_busy && i-- > 0)
            cycle();

        Translation t;
        t.pa = this->dut.RXVMMU->translation_pa(this->dut.i_translation) << 12;
        t.dirty = this->dut.RXVMMU->translation_dirty(this->dut.i_translation);
        t.accessed =
            this->dut.RXVMMU->translation_accessed(this->dut.i_translation);
        t.page_global =
            this->dut.RXVMMU->translation_page_global(this->dut.i_translation);
        t.user = this->dut.RXVMMU->translation_user(this->dut.i_translation);
        t.exec = this->dut.RXVMMU->translation_exec(this->dut.i_translation);
        t.write = this->dut.RXVMMU->translation_write(this->dut.i_translation);
        t.read = this->dut.RXVMMU->translation_read(this->dut.i_translation);
        t.valid = this->dut.RXVMMU->translation_valid(this->dut.i_translation);
        t.asid = this->dut.RXVMMU->translation_asid(this->dut.i_translation);

        return t;
    }

    std::shared_ptr<MemoryBus> bus;
    uint32_t next_free_page;
    uint32_t pgd_base;
};

bool operator==(const MMUTestbench::Translation &lhs,
                const MMUTestbench::Translation &rhs)
{
    return lhs.pa == rhs.pa && lhs.dirty == rhs.dirty &&
           lhs.accessed == rhs.accessed && lhs.page_global == rhs.page_global &&
           lhs.user == rhs.user && lhs.exec == rhs.exec &&
           lhs.write == rhs.write && lhs.read == rhs.read &&
           lhs.valid == rhs.valid && lhs.asid == rhs.asid;
}

TEST_F(MMUTestbench, Page)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = d_translate(0xc0004000);
    auto t2 = d_translate(0xc0004000);

    EXPECT_EQ(t1, t2);
}

TEST_F(MMUTestbench, MegaPage)
{
    enable();

    set_megapage_at(0xc0000000, 0x80000000, pte_read | pte_write | pte_user);

    auto t1 = d_translate(0xc0024000);

    EXPECT_EQ(t1.pa, 0x80024000);
}

TEST_F(MMUTestbench, CachedTranslation)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = d_translate(0xc0004000);

    set_page_at(0xc0004000, 0x80000000, pte_read);
    dcache_inval();
    auto t2 = d_translate(0xc0004000);

    EXPECT_EQ(t1, t2);
}

TEST_F(MMUTestbench, ASIDAlias)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    this->dut.active_asid = 1;
    d_translate(0xc0004000);

    this->dut.active_asid = 2;
    set_page_at(0xc0004000, 0x80000000, pte_read);
    dcache_inval();
    d_translate(0xc0004000);

    this->dut.active_asid = 1;
    auto t1 = d_translate(0xc0004000);
    this->dut.active_asid = 2;
    auto t2 = d_translate(0xc0004000);

    EXPECT_EQ(t1.pa, 0x80012000);
    EXPECT_EQ(t2.pa, 0x80000000);
}

TEST_F(MMUTestbench, GlobalMappings)
{
    enable();

    set_page_at(0xc0004000, 0x80012000,
                pte_read | pte_write | pte_user | pte_global);

    this->dut.active_asid = 1;
    auto t1 = d_translate(0xc0004000);

    this->dut.active_asid = 2;
    set_page_at(0xc0004000, 0, 0);
    dcache_inval();

    auto t2 = d_translate(0xc0004000);

    EXPECT_EQ(t1, t2);
}

TEST_F(MMUTestbench, PageNotMapped)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = d_translate(0x40000000);
    EXPECT_FALSE(t1.valid);
    auto t2 = d_translate(0xc0004000);
    EXPECT_TRUE(t2.valid);
    EXPECT_EQ(t2.pa, 0x80012000);
}

TEST_F(MMUTestbench, InvalidPTE)
{
    enable();

    set_page_at(0xc0004000, 0x80012000,
                pte_read | pte_write | pte_user | (3 << 8));

    auto t = d_translate(0xc0004000);
    EXPECT_FALSE(t.valid);
}

TEST_F(MMUTestbench, Bypass)
{
    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);
    auto t = d_translate(0xc0004000);
    EXPECT_TRUE(t.valid);
    EXPECT_EQ(0xc0004000, t.pa);
}

TEST_F(MMUTestbench, InstructionTranslation)
{
    set_page_at(0xc0004000, 0x80012000,
                pte_read | pte_write | pte_exec | pte_user);
    auto t = i_translate(0xc0004000);
    EXPECT_TRUE(t.valid);
    EXPECT_EQ(0xc0004000, t.pa);
}

TEST_F(MMUTestbench, SimultaneousMiss)
{
    enable();

    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_exec);
    set_page_at(0x000a0000, 0x800cc000,
                pte_read | pte_write | pte_exec | pte_user);

    after_n_cycles(0, [&] {
        this->dut.i_va = 0xc0004000 >> 12;
        this->dut.i_valid = 1;
        this->dut.d_va = 0x000a0000 >> 12;
        this->dut.d_valid = 1;
        after_n_cycles(1, [&] {
            this->dut.i_valid = 0;
            this->dut.d_valid = 0;
        });
    });
    cycle(3);

    uint32_t i_pa = 0;
    uint32_t d_pa = 0;
    bool i_finished = false;
    bool d_finished = false;

    int i = 1024;
    do {
        if (!this->dut.i_busy && !i_finished) {
            i_pa = this->dut.RXVMMU->translation_pa(this->dut.i_translation)
                   << 12;
            i_finished = true;
        }
        if (!this->dut.d_busy && !d_finished) {
            d_pa = this->dut.RXVMMU->translation_pa(this->dut.d_translation)
                   << 12;
            d_finished = true;
        }
        cycle();
    } while (!(i_finished && d_finished) && i-- > 0);
    ASSERT_TRUE(i > 0);

    EXPECT_EQ(i_pa, 0x80012000);
    EXPECT_EQ(d_pa, 0x800cc000);
}