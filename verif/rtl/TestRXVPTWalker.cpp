#include "VerilogTestbench.h"
#include "VRXVPTWalkerWrapper.h"
#include "VRXVPTWalkerWrapper_RXVPTWalkerWrapper.h"
#include "VRXVPTWalkerWrapper_BusTransactor.h"
#include "RXVSim.h"

static inline uint32_t vpn0(uint32_t va)
{
    return (va >> 12) & 0x3ff;
}

static inline uint32_t vpn1(uint32_t va)
{
    return (va >> 22) & 0x3ff;
}

class PTWalkerTestbench
    : public VerilogTestbench<VRXVPTWalkerWrapper>
    , public ::testing::Test
{
public:
    PTWalkerTestbench() : next_free_page(0x80000000)
    {
        this->dut.valid = 0;
        pgd_base = alloc_page();
        this->dut.translation_base = pgd_base >> 12;
        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024);
        this->dut.RXVPTWalkerWrapper->BusTransactor->set_bus(bus);
    }

    uint32_t alloc_page()
    {
        auto r = next_free_page;

        next_free_page += 4096;

        return r;
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
        uint32_t pte;
        bool is_megapage;
        bool translation_error;
    };

    Translation translate(uint32_t va)
    {
        after_n_cycles(0, [&] {
            this->dut.va = va >> 12;
            this->dut.valid = 1;
            after_n_cycles(1, [&] { this->dut.valid = 0; });
        });
        cycle(2);

        while (this->dut.busy)
            cycle();

        Translation t;

        t.pte = this->dut.pte_out;
        t.is_megapage = this->dut.is_megapage;
        t.translation_error = this->dut.translation_error;

        return t;
    }

    std::shared_ptr<MemoryBus> bus;
    uint32_t next_free_page;
    uint32_t pgd_base;
};

bool operator==(const PTWalkerTestbench::Translation &lhs,
                const PTWalkerTestbench::Translation &rhs)
{
    return lhs.pte == rhs.pte && lhs.is_megapage == rhs.is_megapage &&
           lhs.translation_error == rhs.translation_error;
}

TEST_F(PTWalkerTestbench, InvalidPageError)
{
    auto t = translate(0xc0000000);
    EXPECT_TRUE(t.translation_error);
}

TEST_F(PTWalkerTestbench, UnmappedPage)
{
    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t = translate(0xc0004000);
    EXPECT_FALSE(t.translation_error);

    t = translate(0xc0005000);
    EXPECT_TRUE(t.translation_error);
}

TEST_F(PTWalkerTestbench, Megapage)
{
    set_megapage_at(0xc0000000, 0x80400000, pte_read | pte_write | pte_user);

    auto t = translate(0xc0000000);
    EXPECT_EQ(t.pte, 0x20100017);
    EXPECT_FALSE(t.translation_error);
    EXPECT_TRUE(t.is_megapage);
}

TEST_F(PTWalkerTestbench, MisalignedMegapage)
{
    set_megapage_at(0xc0000000, 0x80001000, pte_read | pte_write | pte_user);

    auto t = translate(0xc0000000);
    EXPECT_TRUE(t.translation_error);
}

TEST_F(PTWalkerTestbench, Page)
{
    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t = translate(0xc0004000);
    EXPECT_EQ(t.pte, 0x20004817);
    EXPECT_FALSE(t.translation_error);
    EXPECT_FALSE(t.is_megapage);
}

TEST_F(PTWalkerTestbench, WalkIdempotency)
{
    set_page_at(0xc0004000, 0x80012000, pte_read | pte_write | pte_user);

    auto t1 = translate(0xc0004000);
    auto t2 = translate(0xc0004000);
    EXPECT_EQ(t1, t2);
}