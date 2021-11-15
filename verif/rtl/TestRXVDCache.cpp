#include "VerilogTestbench.h"
#include "VRXVDCacheWrapper.h"
#include "VRXVDCacheWrapper_RXVDCacheWrapper.h"
#include "VRXVDCacheWrapper_BusTransactor.h"
#include "MockMemoryBus.h"

static const int nr_lines = 4;
static const int nr_ways = 4;
static const int line_size_bytes = 16;

class DCacheTestbench
    : public VerilogTestbench<VRXVDCacheWrapper>
    , public ::testing::Test
{
public:
    DCacheTestbench()
    {
        this->dut.invalidate = 0;
        this->dut.valid = 0;
        reset();
        bus = std::make_shared<::testing::StrictMock<MockMemoryBus>>();
        this->dut.RXVDCacheWrapper->BusTransactor->set_bus(bus);
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
            this->dut.din = data;
            this->dut.bytesel = bytesel;
            this->dut.wren = 1;

            after_n_cycles(1, [&] {
                this->dut.valid = 0;
                this->dut.wren = 0;
            });
        });
        cycle();

        int i = 0;
        do {
            cycle();
        } while (this->dut.busy && ++i < 256);

        // One additional cycle of latency before the data is written
        cycle();
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

        int i = 0, word = 0, idle_cycles = 0;
        do {
            if (word < addresses.size()) {
                after_n_cycles(0, [&] {
                    this->dut.address = addresses[word++] >> 2;
                    this->dut.valid = 1;
                    this->dut.wren = 0;
                });
            } else {
                after_n_cycles(0, [&] {
                    this->dut.valid = 0;
                    this->dut.wren = 0;
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
};

TEST_F(DCacheTestbench, CompulsoryMissFills)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
}

TEST_F(DCacheTestbench, HitNoRefill)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    for (int i = 0; i < 128; ++i)
        EXPECT_EQ(read(32), 0xa5a50000);
}

TEST_F(DCacheTestbench, ConflictMissRefill)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(64 + i * 4))
            .WillOnce(::testing::Return(0xaa550000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    v = read(64);
    EXPECT_EQ(v, 0xaa550000);
}

TEST_F(DCacheTestbench, PipelinedReads)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    EXPECT_EQ(read(32), 0xa5a50000);
    auto v = read_pipelined(std::vector<uint32_t>{36, 40});
    EXPECT_THAT(v, ::testing::ElementsAre(0xa5a50001, 0xa5a50002));

    cycle(32);
}

TEST_F(DCacheTestbench, ReadDuringBusyDropped)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read_pipelined(std::vector<uint32_t>{32, 36, 32});
    EXPECT_THAT(v, ::testing::ElementsAre(0xa5a50000, 0xa5a50000, 0xa5a50000));

    cycle(32);
}

TEST_F(DCacheTestbench, MultiWayHits)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + 4096 + i * 4))
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

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + 4096 + i * 4))
            .WillOnce(::testing::Return(0xf00f0000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    v = read(4096 + 32);
    EXPECT_EQ(v, 0xf00f0000);

    // From a different way, should not require re-fetching
    write(32, 0xd00df00d);
    write(4096 + 32, 0xd00df00d);

    cycle(8);
}

TEST_F(DCacheTestbench, InvalidateRefills)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
    write(32, 0xdeadbeef);
    invalidate();

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
}

TEST_F(DCacheTestbench, IdleNoLineFill)
{
    // Should generate no line-fills
    cycle(256);
    EXPECT_FALSE(this->dut.busy);
}

TEST_F(DCacheTestbench, NoFillWithoutValid)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);

    this->dut.address = 48;
    cycle(256);
    EXPECT_EQ(this->dut.dout, 0x00000000);
}

TEST_F(DCacheTestbench, WriteFills)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    write(32, 0xdeadbeef);
}

TEST_F(DCacheTestbench, WriteUpdates)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    write(32, 0xdeadbeef);
    auto v = read(32);
    EXPECT_EQ(v, 0xdeadbeef);
}

TEST_F(DCacheTestbench, WriteBytesel)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    write(32, 0xdeadbeef);
    EXPECT_EQ(read(32), 0xdeadbeef);
    write(32, 0, 0x6);
    EXPECT_EQ(read(32), 0xde0000ef);
}

TEST_F(DCacheTestbench, MultiIndex)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xf00ff00f + i));
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(48 + i * 4))
            .WillOnce(::testing::Return(0xf00ff00f + i));

    write(32, 0xdead0000);
    write(48, 0x0000beef);

    EXPECT_EQ(read(32), 0xdead0000);
    EXPECT_EQ(read(48), 0x0000beef);
}

TEST_F(DCacheTestbench, WriteConflictWritesBack)
{
    ::testing::InSequence seq;

    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < line_size_bytes / sizeof(uint32_t); ++j)
            EXPECT_CALL(*this->bus, read((4096 * i) + (j * 4)))
                .WillOnce(::testing::Return(i << 16 | j));
    }

    // Fill each way at the same index
    for (int i = 0; i < 4; ++i)
        EXPECT_EQ(read(4096 * i), i << 16);

    // Dirty all ways
    for (int i = 0; i < 4; ++i)
        write(4096 * i, 0xf00ff00f);

    // Expect write-back
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(i * 4, i == 0 ? 0xf00ff00f : i, 0xf));

    // Expect line-fill
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(0x1000000 + i * 4))
            .WillOnce(::testing::Return(0x10001000 + i));

    EXPECT_EQ(read(0x1000000), 0x10001000);
}

TEST_F(DCacheTestbench, NoDirtyNoWritebackOnClean)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    read(32);
    clean();
}

TEST_F(DCacheTestbench, CleanWritesBackDirty)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(32 + i * 4, 0xf00ff00f, 0xf));

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        write(32 + i * 4, 0xf00ff00f);

    clean();
}

TEST_F(DCacheTestbench, RepeatedCleanDirty)
{
    ::testing::InSequence seq;

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4))
            .WillOnce(::testing::Return(0xa5a50000 + i));
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(32 + i * 4, 0xf00ff00f, 0xf));

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        write(32 + i * 4, 0xf00ff00f);

    clean();

    // Re-dirty
    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        write(32 + i * 4, i);

    for (int i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, write(32 + i * 4, i, 0xf));
    clean();
}

TEST_F(DCacheTestbench, UncachedReadNoFill)
{
    ::testing::InSequence seq;

    EXPECT_CALL(*this->bus, read(0xf0000000))
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
}

TEST_F(DCacheTestbench, UncachedWriteSubWord)
{
    ::testing::InSequence seq;

    EXPECT_CALL(*this->bus, write(0xf0000000, 0xf00ff00f, 0x1));
    write(0xf0000000, 0xf00ff00f, 0x1);
    cycle(8);
}