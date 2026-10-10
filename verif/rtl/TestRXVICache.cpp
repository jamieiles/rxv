// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include "VerilogTestbench.h"
#include "VRXVICacheWrapper.h"
#include "VRXVICacheWrapper__Dpi.h"
#include "VRXVICacheWrapper_RXVICacheWrapper.h"
#include "VRXVICacheWrapper_BusTransactor__Iz1.h"
#include "MockMemoryBus.h"
#include "SVUtils.h"

static const int nr_lines = 2;
static const int nr_ways = 2;
static const int line_size_bytes = 16;

class ICacheTestbench
    : public VerilogTestbench<VRXVICacheWrapper>
    , public ::testing::Test
{
public:
    ICacheTestbench() : access_count(0), miss_count(0)
    {
        this->dut.invalidate = 0;
        this->dut.valid = 0;
        reset();
        bus = std::make_shared<::testing::StrictMock<MockMemoryBus>>();
        sv_set_scope_name("TOP.RXVICacheWrapper.BusTransactor");
        this->dut.dpi_set_bus(bus.get());

        periodic(ClockCapture, [&] {
            if (this->dut.valid) {
                uint32_t addr = this->dut.address;
                after_n_cycles(1, [&, addr] {
                    this->dut.phys_valid = 1;
                    this->dut.phys_in = addr;
                    after_n_cycles(1, [&, addr] { this->dut.phys_valid = 0; });
                });
            }

            if (this->dut.pmu_icache_access)
                ++access_count;
            if (this->dut.pmu_icache_miss)
                ++miss_count;
        });
    }

    uint32_t read(uint32_t addr)
    {
        after_n_cycles(0, [&] {
            this->dut.address = addr >> 2;
            this->dut.valid = 1;
            this->dut.invalidate = 0;

            after_n_cycles(1, [&] { this->dut.valid = 0; });
        });
        cycle();

        int i = 0;
        do {
            cycle();
        } while (this->dut.busy && ++i < 256);

        EXPECT_LT(i, 256);

        return this->dut.dout;
    }

    void invalidate()
    {
        after_n_cycles(0, [&] {
            this->dut.invalidate = 1;
            after_n_cycles(1, [&] { this->dut.invalidate = 0; });
        });
        cycle();

        int i = 0;
        do {
            cycle();
        } while (this->dut.busy && ++i < 2048);

        EXPECT_LT(i, 2048);
    }

    std::vector<uint32_t> read_pipelined(std::vector<uint32_t> addresses)
    {
        std::vector<uint32_t> data;

        this->dut.invalidate = 0;

        size_t i = 0, word = 0;
        do {
            if (word < addresses.size()) {
                after_n_cycles(0, [&] {
                    this->dut.address = addresses[word++] >> 2;
                    this->dut.valid = 1;
                });
            } else {
                after_n_cycles(0, [&] { this->dut.valid = 0; });
            }
            cycle();

            if (i > 0 && !this->dut.busy)
                data.push_back(this->dut.dout);
        } while (data.size() != addresses.size() && i++ < 256);

        EXPECT_LT(i, 256);

        return data;
    }

    std::shared_ptr<MockMemoryBus> bus;
    uint64_t access_count;
    uint64_t miss_count;
};

TEST_F(ICacheTestbench, CompulsoryMissFills)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    EXPECT_EQ(access_count, 1);
    EXPECT_EQ(miss_count, 1);
}

TEST_F(ICacheTestbench, HitNoRefill)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    for (int i = 0; i < 128; ++i)
        EXPECT_EQ(read(32), 0xa5a50000);

    EXPECT_EQ(access_count, 128);
    EXPECT_EQ(miss_count, 1);
}

TEST_F(ICacheTestbench, ConflictMissRefill)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(64 + i * 4, true))
            .WillOnce(::testing::Return(0xaa550000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    v = read(64);
    EXPECT_EQ(v, 0xaa550000);
}

TEST_F(ICacheTestbench, PipelinedReads)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    EXPECT_EQ(read(32), 0xa5a50000);
    auto v = read_pipelined(std::vector<uint32_t>{36, 40});
    EXPECT_THAT(v, ::testing::ElementsAre(0xa5a50001, 0xa5a50002));

    cycle(32);

    EXPECT_EQ(access_count, 3);
    EXPECT_EQ(miss_count, 1);
}

TEST_F(ICacheTestbench, ReadDuringBusyDropped)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read_pipelined(std::vector<uint32_t>{32, 36 + 1024, 32});
    EXPECT_THAT(v, ::testing::ElementsAre(0xa5a50000, 0xa5a50000, 0xa5a50000));

    cycle(32);
}

TEST_F(ICacheTestbench, MultiWayHits)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + 4096 + i * 4, true))
            .WillOnce(::testing::Return(0xf00f0000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    v = read(4096 + 32);
    EXPECT_EQ(v, 0xf00f0000);

    // From a different way, should not require re-fetching
    v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
}

TEST_F(ICacheTestbench, InvalidateRefills)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    invalidate();

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
}

TEST_F(ICacheTestbench, IdleNoLineFill)
{
    // Should generate no line-fills
    cycle(256);
    EXPECT_FALSE(this->dut.busy);
    EXPECT_EQ(access_count, 0);
    EXPECT_EQ(miss_count, 0);
}

TEST_F(ICacheTestbench, NoFillWithoutValid)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    this->dut.address = 36;
    cycle(256);
    EXPECT_EQ(this->dut.dout, 0);
}

TEST_F(ICacheTestbench, MultiIndex)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xdead0000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(48 + i * 4, true))
            .WillOnce(::testing::Return(0x0000beef + i));

    EXPECT_EQ(read(32), 0xdead0000);
    EXPECT_EQ(read(48), 0x0000beef);
    cycle();
}

// Hits must update the PLRU state of the set that hit even when the next
// fetch is to a different set.
TEST_F(ICacheTestbench, PLRUUpdatesHitSet)
{
    auto expect_fill = [&](uint32_t addr) {
        for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
            EXPECT_CALL(*this->bus, read(addr + i * 4, true))
                .WillOnce(::testing::Return((addr << 16) + i));
    };

    ::testing::InSequence seq;

    for (uint32_t a : {0x10, 0x00, 0x40, 0x80, 0xc0, 0x100, 0x40})
        expect_fill(a);

    // Ways are filled in PLRU order: 0x00 in way 3 down to 0xc0 in way 0
    // which is then the only most recently used way.
    for (uint32_t a : {0x10, 0x00, 0x40, 0x80, 0xc0})
        EXPECT_EQ(read(a), a << 16);

    // Touch 0x00 immediately followed by a fetch from set 1 so 0x40 becomes
    // the PLRU victim in set 0.
    auto v = read_pipelined(std::vector<uint32_t>{0x00, 0x10});
    EXPECT_THAT(v, ::testing::ElementsAre(0x00 << 16, 0x10 << 16));

    // Evicts 0x40, 0x00 should still hit.
    EXPECT_EQ(read(0x100), 0x100 << 16);
    EXPECT_EQ(read(0x00), 0x00 << 16);
    EXPECT_EQ(read(0x40), 0x40 << 16);
}
