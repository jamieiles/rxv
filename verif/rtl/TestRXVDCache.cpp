// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include "VerilogTestbench.h"
#include "VRXVDCacheWrapper.h"
#include "VRXVDCacheWrapper__Dpi.h"
#include "VRXVDCacheWrapper_RXVDCacheWrapper.h"
#include "VRXVDCacheWrapper_BusTransactor.h"
#include "MockMemoryBus.h"
#include "SVUtils.h"

static const int nr_lines = 4;
static const int nr_ways = 4;
static const int line_size_bytes = 16;

class DCacheTestbench
    : public VerilogTestbench<VRXVDCacheWrapper>
    , public ::testing::Test
{
public:
    DCacheTestbench()
        : wr_access_count(0)
        , wr_miss_count(0)
        , rd_access_count(0)
        , rd_miss_count(0)
    {
        this->dut.invalidate = 0;
        this->dut.valid = 0;
        reset();
        bus = std::make_shared<::testing::StrictMock<MockMemoryBus>>();
        sv_set_scope_name("TOP.RXVDCacheWrapper.BusTransactor");
        this->dut.dpi_set_bus(bus.get());

        periodic(ClockCapture, [&] {
            if (this->dut.pmu_dcache_wr_access)
                ++wr_access_count;
            if (this->dut.pmu_dcache_wr_miss)
                ++wr_miss_count;
            if (this->dut.pmu_dcache_rd_access)
                ++rd_access_count;
            if (this->dut.pmu_dcache_rd_miss)
                ++rd_miss_count;
        });
    }

    uint32_t read(uint32_t addr)
    {
        after_n_cycles(0, [&] {
            this->dut.address = addr >> 2;
            this->dut.valid = 1;
            this->dut.invalidate = 0;
            this->dut.wren = 0;

            after_n_cycles(1, [&] {
                this->dut.valid = 0;
                this->dut.wren = 0;
                this->dut.phys_in = addr >> 2;
                this->dut.phys_valid = 1;
            });
        });
        cycle();

        int i = 0;
        do {
            cycle();
        } while (this->dut.busy && ++i < 256);

        // One additional cycle of latency before the data is available
        cycle();

        EXPECT_LT(i, 256);

        return this->dut.dout;
    }

    void write(uint32_t addr, uint32_t data, uint8_t bytesel = 0xf)
    {
        after_n_cycles(0, [&] {
            this->dut.address = addr >> 2;
            this->dut.valid = 1;
            this->dut.invalidate = 0;

            after_n_cycles(1, [&] {
                this->dut.valid = 0;
                this->dut.bytesel = bytesel;
                this->dut.wren = 1;
                this->dut.din = data;
                this->dut.phys_in = addr >> 2;
                this->dut.phys_valid = 1;
            });
        });
        cycle();

        int i = 0;
        do {
            cycle();
        } while (this->dut.busy && ++i < 256);
        after_n_cycles(0, [&] { this->dut.wren = 0; });

        // One additional cycle of latency before the data is written
        cycle();
    }

    // Cache-block flush: an access with flush set in the tag compare cycle
    void flush(uint32_t addr)
    {
        after_n_cycles(0, [&] {
            this->dut.address = addr >> 2;
            this->dut.valid = 1;
            this->dut.invalidate = 0;
            this->dut.wren = 0;

            after_n_cycles(1, [&] {
                this->dut.valid = 0;
                this->dut.flush = 1;
                this->dut.phys_in = addr >> 2;
                this->dut.phys_valid = 1;
            });
        });
        cycle();

        int i = 0;
        do {
            cycle();
        } while (this->dut.busy && ++i < 256);
        after_n_cycles(0, [&] { this->dut.flush = 0; });
        cycle();

        EXPECT_LT(i, 256);
    }

    void expect_line_fill(uint32_t addr, uint32_t base)
    {
        for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
            EXPECT_CALL(*this->bus, read(addr + i * 4, false))
                .WillOnce(::testing::Return(base + i));
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

    void clean()
    {
        after_n_cycles(0, [&] {
            this->dut.clean = 1;
            after_n_cycles(1, [&] { this->dut.clean = 0; });
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

        size_t i = 0, word = 0, idle_cycles = 0;
        do {
            if (word < addresses.size()) {
                uint32_t addr = addresses[word];
                after_n_cycles(0, [&, addr] {
                    this->dut.address = addr >> 2;
                    this->dut.valid = 1;
                    this->dut.wren = 0;
                    after_n_cycles(1, [&, addr] {
                        this->dut.phys_in = addr >> 2;
                        this->dut.phys_valid = 1;
                    });
                });
                ++word;
            } else {
                after_n_cycles(0, [&] {
                    this->dut.valid = 0;
                    this->dut.wren = 0;
                    this->dut.phys_valid = 1;
                    after_n_cycles(1, [&] { this->dut.phys_valid = 0; });
                });
            }
            cycle();

            if (idle_cycles >= 2)
                data.push_back(this->dut.dout);
            // Data out is not valid until 2 cycles after busy goes low
            if (!this->dut.busy)
                ++idle_cycles;
        } while (data.size() != addresses.size() && i++ < 256);

        EXPECT_LT(i, 256);

        return data;
    }

    std::shared_ptr<MockMemoryBus> bus;
    uint64_t wr_access_count;
    uint64_t wr_miss_count;
    uint64_t rd_access_count;
    uint64_t rd_miss_count;
};

TEST_F(DCacheTestbench, CompulsoryMissFills)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    EXPECT_EQ(1, rd_access_count);
    EXPECT_EQ(1, rd_miss_count);
    EXPECT_EQ(0, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
}

TEST_F(DCacheTestbench, HitNoRefill)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    for (int i = 0; i < 128; ++i)
        EXPECT_EQ(read(32), 0xa5a50000);

    EXPECT_EQ(128, rd_access_count);
    EXPECT_EQ(1, rd_miss_count);
    EXPECT_EQ(0, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
}

TEST_F(DCacheTestbench, ConflictMissRefill)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(64 + i * 4, false))
            .WillOnce(::testing::Return(0xaa550000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    v = read(64);
    EXPECT_EQ(v, 0xaa550000);

    EXPECT_EQ(2, rd_access_count);
    EXPECT_EQ(2, rd_miss_count);
    EXPECT_EQ(0, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
}

TEST_F(DCacheTestbench, PipelinedReads)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    EXPECT_EQ(read(32), 0xa5a50000);
    auto v = read_pipelined(std::vector<uint32_t>{36, 40});
    EXPECT_THAT(v, ::testing::ElementsAre(0xa5a50001, 0xa5a50002));

    cycle(32);

    EXPECT_EQ(3, rd_access_count);
    EXPECT_EQ(1, rd_miss_count);
    EXPECT_EQ(0, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
}

TEST_F(DCacheTestbench, ReadDuringBusyDropped)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read_pipelined(std::vector<uint32_t>{32, 36, 32});
    EXPECT_THAT(v, ::testing::ElementsAre(0xa5a50000, 0xa5a50000, 0xa5a50000));

    cycle(32);
}

TEST_F(DCacheTestbench, MultiWayHits)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + 4096 + i * 4, false))
            .WillOnce(::testing::Return(0xf00f0000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    v = read(4096 + 32);
    EXPECT_EQ(v, 0xf00f0000);

    // From a different way, should not require re-fetching
    v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
}

TEST_F(DCacheTestbench, MultiWayHitWrites)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + 4096 + i * 4, false))
            .WillOnce(::testing::Return(0xf00f0000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    v = read(4096 + 32);
    EXPECT_EQ(v, 0xf00f0000);

    // From a different way, should not require re-fetching
    write(32, 0xd00df00d);
    write(4096 + 32, 0xd00df00d);

    cycle(8);

    EXPECT_EQ(2, rd_access_count);
    EXPECT_EQ(2, rd_miss_count);
    EXPECT_EQ(2, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
}

TEST_F(DCacheTestbench, InvalidateRefills)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    write(32, 0xdeadbeef);
    invalidate();

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    EXPECT_EQ(2, rd_access_count);
    EXPECT_EQ(2, rd_miss_count);
    EXPECT_EQ(1, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
}

TEST_F(DCacheTestbench, IdleNoLineFill)
{
    // Should generate no line-fills
    cycle(256);
    EXPECT_FALSE(this->dut.busy);
    EXPECT_EQ(0, wr_access_count);
    EXPECT_EQ(0, wr_miss_count);
    EXPECT_EQ(0, rd_access_count);
    EXPECT_EQ(0, rd_miss_count);
}

TEST_F(DCacheTestbench, NoFillWithoutValid)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    this->dut.address = 48;
    cycle(256);
}

TEST_F(DCacheTestbench, WriteFills)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    write(32, 0xdeadbeef);

    EXPECT_EQ(0, rd_access_count);
    EXPECT_EQ(0, rd_miss_count);
    EXPECT_EQ(1, wr_access_count);
    EXPECT_EQ(1, wr_miss_count);
}

TEST_F(DCacheTestbench, WriteUpdates)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    write(32, 0xdeadbeef);
    auto v = read(32);
    EXPECT_EQ(v, 0xdeadbeef);

    EXPECT_EQ(1, rd_access_count);
    EXPECT_EQ(0, rd_miss_count);
    EXPECT_EQ(1, wr_access_count);
    EXPECT_EQ(1, wr_miss_count);
}

TEST_F(DCacheTestbench, WriteBytesel)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    write(32, 0xdeadbeef);
    EXPECT_EQ(read(32), 0xdeadbeef);
    write(32, 0, 0x6);
    EXPECT_EQ(read(32), 0xde0000ef);
}

TEST_F(DCacheTestbench, MultiIndex)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xf00ff00f + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(48 + i * 4, false))
            .WillOnce(::testing::Return(0xf00ff00f + i));

    write(32, 0xdead0000);
    write(48, 0x0000beef);

    EXPECT_EQ(read(32), 0xdead0000);
    EXPECT_EQ(read(48), 0x0000beef);
}

TEST_F(DCacheTestbench, WriteConflictWritesBack)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < 4; ++i) {
        for (size_t j = 0; j < line_size_bytes / sizeof(uint32_t); ++j)
            EXPECT_CALL(*this->bus, read((4096 * i) + (j * 4), false))
                .WillOnce(::testing::Return(i << 16 | j));
    }

    // Fill each way at the same index
    for (size_t i = 0; i < 4; ++i)
        EXPECT_EQ(read(4096 * i), i << 16);

    // Dirty all ways
    for (size_t i = 0; i < 4; ++i)
        write(4096 * i, 0xf00ff00f);

    // Expect write-back
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus,
                    write((4096 * 1) + i * 4,
                          i == 0 ? 0xf00ff00f : (1 << 16) | i, 0xf));

    // Expect line-fill
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(0x1000000 + i * 4, false))
            .WillOnce(::testing::Return(0x10001000 + i));

    EXPECT_EQ(read(0x1000000), 0x10001000);
}

TEST_F(DCacheTestbench, NoDirtyNoWritebackOnClean)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    read(32);
    clean();
}

TEST_F(DCacheTestbench, CleanWritesBackDirty)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(32 + i * 4, 0xf00ff00f, 0xf));

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        write(32 + i * 4, 0xf00ff00f);

    clean();
}

TEST_F(DCacheTestbench, RepeatedCleanDirty)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, false))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(32 + i * 4, 0xf00ff00f, 0xf));

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        write(32 + i * 4, 0xf00ff00f);

    clean();

    // Re-dirty
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        write(32 + i * 4, i);

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(32 + i * 4, i, 0xf));
    clean();
}

TEST_F(DCacheTestbench, UncachedReadNoFill)
{
    ::testing::InSequence seq;

    EXPECT_CALL(*this->bus, read(0xf0000000, false))
        .WillOnce(::testing::Return(0xa5a50000));
    EXPECT_EQ(read(0xf0000000), 0xa5a50000);
    cycle(8);
}

TEST_F(DCacheTestbench, UncachedWriteNoFill)
{
    ::testing::InSequence seq;

    EXPECT_CALL(*this->bus, write(0xf0000000, 0xf00ff00f, 0xf));
    write(0xf0000000, 0xf00ff00f, 0xf);
    cycle(8);

    EXPECT_EQ(0, rd_access_count);
    EXPECT_EQ(0, rd_miss_count);
    EXPECT_EQ(1, wr_access_count);
    EXPECT_EQ(1, wr_miss_count);
}

TEST_F(DCacheTestbench, UncachedWriteSubWord)
{
    ::testing::InSequence seq;

    EXPECT_CALL(*this->bus, write(0xf0000000, 0xf00ff00f, 0x1));
    write(0xf0000000, 0xf00ff00f, 0x1);
    cycle(8);
}

TEST_F(DCacheTestbench, FlushDirtyWritesBackAndInvalidates)
{
    ::testing::InSequence seq;

    expect_line_fill(32, 0xa5a50000);
    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus,
                    write(32 + i * 4, i == 1 ? 0xf00ff00f : 0xa5a50000 + i, 0xf));
    // The line is no longer present so the next read refills it
    expect_line_fill(32, 0x5a5a0000);

    write(36, 0xf00ff00f);
    // Any address within the line selects it
    flush(40);

    EXPECT_EQ(read(36), 0x5a5a0001);
}

TEST_F(DCacheTestbench, FlushCleanInvalidatesWithoutWriteback)
{
    ::testing::InSequence seq;

    expect_line_fill(32, 0xa5a50000);
    expect_line_fill(32, 0x5a5a0000);

    EXPECT_EQ(read(32), 0xa5a50000);
    flush(32);
    EXPECT_EQ(read(32), 0x5a5a0000);

    // The flush is neither a read nor a write access
    EXPECT_EQ(2, rd_access_count);
    EXPECT_EQ(2, rd_miss_count);
    EXPECT_EQ(0, wr_access_count);
}

TEST_F(DCacheTestbench, FlushMissNoBusAccess)
{
    // Strict mock: any fill or write-back fails the test
    flush(64);
    cycle(32);
}

TEST_F(DCacheTestbench, FlushDeviceMemoryNoBusAccess)
{
    flush(0xf0000000);
    cycle(32);
}

TEST_F(DCacheTestbench, FlushOnlyHitWay)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < 4; ++i)
        expect_line_fill(4096 * i, i << 16);

    for (size_t i = 0; i < 4; ++i)
        EXPECT_EQ(read(4096 * i), i << 16);
    for (size_t i = 0; i < 4; ++i)
        write(4096 * i, 0xf00ff00f + i);

    for (size_t j = 0; j < line_size_bytes / sizeof(uint32_t); ++j)
        EXPECT_CALL(*this->bus,
                    write(4096 * 2 + j * 4, j == 0 ? 0xf00ff011 : (2 << 16) | j, 0xf));
    flush(4096 * 2);

    // The other ways are still present and dirty
    for (size_t i = 0; i < 4; ++i) {
        if (i != 2) {
            EXPECT_EQ(read(4096 * i), 0xf00ff00f + i);
        }
    }

    expect_line_fill(4096 * 2, 0x22220000);
    EXPECT_EQ(read(4096 * 2), 0x22220000);
}
