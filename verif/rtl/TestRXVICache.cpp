#include "VerilogTestbench.h"
#include "VRXVICacheWrapper.h"
#include "VRXVICacheWrapper_RXVICacheWrapper.h"
#include "VRXVICacheWrapper_BusTransactor__Iz1.h"
#include "MockMemoryBus.h"

static const int nr_lines = 2;
static const int nr_ways = 2;
static const int line_size_bytes = 16;

class ICacheTestbench
    : public VerilogTestbench<VRXVICacheWrapper>
    , public ::testing::Test
{
public:
    ICacheTestbench()
    {
        this->dut.invalidate = 0;
        this->dut.valid = 0;
        reset();
        bus = std::make_shared<::testing::StrictMock<MockMemoryBus>>();
        this->dut.RXVICacheWrapper->BusTransactor->set_bus(bus);

        periodic(ClockCapture, [&] {
            if (this->dut.valid) {
                uint32_t addr = this->dut.address;
                after_n_cycles(1, [&, addr] {
                    this->dut.phys_valid = 1;
                    this->dut.phys_in = addr;
                    after_n_cycles(1, [&, addr] { this->dut.phys_valid = 0; });
                });
            }
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
};

TEST_F(ICacheTestbench, CompulsoryMissFills)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    auto v = read(32);
    EXPECT_EQ(v, 0xa5a50000);
}

TEST_F(ICacheTestbench, HitNoRefill)
{
    ::testing::InSequence seq;

    for (size_t i = 0; i < line_size_bytes / sizeof(uint32_t); ++i)
        EXPECT_CALL(*this->bus, read(32 + i * 4, true))
            .WillOnce(::testing::Return(0xa5a50000 + i));

    for (int i = 0; i < 128; ++i)
        EXPECT_EQ(read(32), 0xa5a50000);
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