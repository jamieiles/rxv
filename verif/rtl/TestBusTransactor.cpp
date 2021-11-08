#include "VerilogTestbench.h"
#include "VBusTransactorWrapper.h"
#include "VBusTransactorWrapper_BusTransactorWrapper.h"
#include "VBusTransactorWrapper_BusTransactor.h"
#include "MemoryDevice.h"
#include "MockMemoryBus.h"

class BusTransactorTest
    : public VerilogTestbench<VBusTransactorWrapper>
    , public ::testing::Test
{
public:
    static const int num_words = 1024;

    BusTransactorTest()
    {
        this->dut.bready = 1;
        this->dut.rready = 1;
        reset();
        bus = std::make_shared<::testing::StrictMock<MockMemoryBus>>();
        this->dut.BusTransactorWrapper->BusTransactor->set_bus(bus);
    }

    void write(uint32_t addr, const std::vector<uint32_t> &val)
    {
        int sent = 0;

        after_n_cycles(0, [&, addr, val] {
            this->dut.waddr = addr;
            this->dut.awvalid = 1;
            this->dut.wlen = val.size() - 1;

            after_n_cycles(1, [&, addr, val] {
                this->dut.awvalid = 0;
                this->dut.wvalid = 1;
                this->dut.wdata = val[0];
                this->dut.wstb = 0xf;
                this->dut.wlast = val.size() == 1;
            });
        });

        do {
            cycle();
            if (this->dut.wready && ++sent != val.size()) {
                after_n_cycles(0,
                               [&, val, sent] { this->dut.wdata = val[sent]; });
                if (sent == val.size() - 1)
                    after_n_cycles(0, [&, val, sent] { this->dut.wlast = 1; });
            }
        } while (sent != val.size());

        after_n_cycles(0, [&] {
            this->dut.wlast = 0;
            this->dut.wvalid = 0;
        });

        int i = 0;
        do {
            cycle();
        } while (!this->dut.bvalid && ++i < 64);

        cycle();
    }

    std::vector<uint32_t> read(uint32_t addr, size_t len)
    {
        std::vector<uint32_t> vals;
        int received = 0;

        after_n_cycles(0, [&, addr] {
            this->dut.raddr = addr;
            this->dut.arvalid = 1;
            this->dut.rlen = len - 1;

            after_n_cycles(1, [&, addr] { this->dut.arvalid = 0; });
        });

        int c = 0;
        do {
            if (this->dut.rvalid) {
                vals.push_back(this->dut.rdata);
                received++;
            }
            if (received == len) {
                EXPECT_TRUE(this->dut.rlast);
            }
            cycle();
        } while (received != len && c++ < 128);

        EXPECT_FALSE(this->dut.rlast);
        EXPECT_FALSE(this->dut.rvalid);

        return vals;
    }

    std::shared_ptr<MockMemoryBus> bus;
};

TEST_F(BusTransactorTest, WriteSingle)
{
    EXPECT_CALL(*this->bus, write(0x10, 0x12345678, 0xf));
    EXPECT_CALL(*this->bus, write(0x14, 0xa5a5aa55, 0xf));
    write(0x10, std::vector<uint32_t>{0x12345678});
    write(0x14, std::vector<uint32_t>{0xa5a5aa55});
    cycle(32);
}

TEST_F(BusTransactorTest, WriteDouble)
{
    EXPECT_CALL(*this->bus, write(0x10, 0x12345678, 0xf)).Times(1);
    EXPECT_CALL(*this->bus, write(0x14, 0xabcdabcd, 0xf)).Times(1);
    std::vector<uint32_t> vals{0x12345678, 0xabcdabcd};
    write(0x10, vals);
    cycle(32);
}

TEST_F(BusTransactorTest, ReadSingle)
{
    EXPECT_CALL(*this->bus, read(0x10)).WillOnce(::testing::Return(0xdeadbeef));
    EXPECT_CALL(*this->bus, read(0x14)).WillOnce(::testing::Return(0x12345678));

    auto v = read(0x10, 1);
    ASSERT_EQ(1, v.size());
    EXPECT_EQ(v[0], 0xdeadbeef);

    v = read(0x14, 1);
    ASSERT_EQ(1, v.size());
    EXPECT_EQ(v[0], 0x12345678);

    cycle(32);
}

TEST_F(BusTransactorTest, ReadDouble)
{
    EXPECT_CALL(*this->bus, read(0x10)).WillOnce(::testing::Return(0x12345678));
    EXPECT_CALL(*this->bus, read(0x14)).WillOnce(::testing::Return(0xabcdabcd));

    auto v = read(0x10, 2);
    ASSERT_EQ(2, v.size());
    EXPECT_THAT(v, ::testing::ElementsAre(0x12345678, 0xabcdabcd));

    cycle(32);
}

TEST_F(BusTransactorTest, WriteToRead)
{
    EXPECT_CALL(*this->bus, write(0x10, 0x12345678, 0xf)).Times(1);
    EXPECT_CALL(*this->bus, read(0x10)).WillOnce(::testing::Return(0x12345678));

    write(0x10, std::vector<uint32_t>{0x12345678});
    auto v = read(0x10, 1);
    EXPECT_THAT(v, ::testing::ElementsAre(0x12345678));
    cycle(32);
}

TEST_F(BusTransactorTest, ReadToWrite)
{
    EXPECT_CALL(*this->bus, read(0x10)).WillOnce(::testing::Return(0x12345678));
    EXPECT_CALL(*this->bus, write(0x10, 0x12345678, 0xf)).Times(1);

    auto v = read(0x10, 1);
    ASSERT_EQ(1, v.size());
    EXPECT_THAT(v, ::testing::ElementsAre(0x12345678));
    write(0x10, std::vector<uint32_t>{0x12345678});
    cycle(32);
}