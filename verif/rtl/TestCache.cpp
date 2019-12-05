#include "VerilogTestbench.h"
#include "VRXVICache.h"

#include <gmock/gmock.h>

class CacheTestbench
    : public VerilogTestbench<VRXVICache>
    , public ::testing::Test
{
public:
    static const int num_words = 1024;

    CacheTestbench()
    {
        periodic(ClockCapture, [&] {
            if (this->dut.cpu_ack) {
                this->dut.cpu_access = 0;
                this->read_vals.push_back(std::make_pair(cur_cycle(), this->dut.cpu_din));
            }

            if (this->dut.bus_request)
                after_n_cycles(1, [&] { this->dut.bus_grant = 1; });
            else
                after_n_cycles(1, [&] { this->dut.bus_grant = 0; });

            after_n_cycles(1, [&] { this->dut.mem_ack = 0; });

            if (!this->dut.mem_access)
                return;

            uint32_t addr = this->dut.mem_addr;
            after_n_cycles(1, [&, addr] {
                this->dut.mem_din = this->mem[addr];
                this->dut.mem_ack = 1;
            });
        });
    }

    void read(uint32_t addr, bool snoop = false, uint32_t snoop_addr = 0)
    {
        auto old_size = read_vals.size();

        after_n_cycles(0, [&, addr, snoop, snoop_addr] {
            this->dut.cpu_access = 1;
            this->dut.cpu_addr = addr;
            this->dut.bus_snoop_req = snoop;
            this->dut.bus_snoop_addr_i = snoop_addr;
            after_n_cycles(1, [&] { this->dut.bus_snoop_req = 0; });
        });

        while (read_vals.size() == old_size)
            cycle();
    }

    void snoop(uint32_t addr){
        after_n_cycles(0, [&, addr] {
            this->dut.bus_snoop_req = 1;
            this->dut.bus_snoop_addr_i = addr;
            after_n_cycles(1, [&] { this->dut.bus_snoop_req = 0; });
        });
        cycle(2);
    }

    uint32_t mem[num_words];
    std::vector<std::pair<vluint64_t, uint32_t>> read_vals;
};

TEST_F(CacheTestbench, SingleRead)
{
    for (auto i = 0; i < num_words; ++i)
        mem[i] = i;

    read(17);

    EXPECT_EQ(read_vals.size(), 1);
    EXPECT_EQ(read_vals[0].second, 17);
}

TEST_F(CacheTestbench, BackToBackReadsCached)
{
    for (auto i = 0; i < num_words; ++i)
        mem[i] = i;

    read(4);
    read(5);

    EXPECT_EQ(read_vals.size(), 2);

    auto initial_latency = read_vals[0].first;
    decltype(this->read_vals) expected;
    expected.push_back(std::make_pair(initial_latency, 4));
    expected.push_back(std::make_pair(initial_latency + 2, 5));

    EXPECT_THAT(expected, ::testing::ContainerEq(read_vals));
}

TEST_F(CacheTestbench, BackToBackReadsCacheMiss)
{
    for (auto i = 0; i < num_words; ++i)
        mem[i] = i;

    read(4);
    read(128);

    EXPECT_EQ(read_vals.size(), 2);
    EXPECT_EQ(read_vals[0].second, 4);
    EXPECT_EQ(read_vals[1].second, 128);
    EXPECT_TRUE(read_vals[1].first - read_vals[0].first > 4);
}

TEST_F(CacheTestbench, SnoopInvalidates)
{
    for (auto i = 0; i < num_words; ++i)
        mem[i] = i;

    read(2);
    snoop(0);
    read(3);

    EXPECT_EQ(read_vals.size(), 2);
    EXPECT_EQ(read_vals[0].second, 2);
    EXPECT_EQ(read_vals[1].second, 3);
    EXPECT_TRUE(read_vals[1].first - read_vals[0].first > 4);
}

TEST_F(CacheTestbench, SimultaneousSnoopInvalidates)
{
    for (auto i = 0; i < num_words; ++i)
        mem[i] = i;

    read(2);
    read(1, true, 0);
    read(3);

    EXPECT_EQ(read_vals.size(), 3);
    EXPECT_EQ(read_vals[0].second, 2);
    EXPECT_EQ(read_vals[1].second, 1);
    EXPECT_EQ(read_vals[2].second, 3);
    EXPECT_TRUE(read_vals[2].first - read_vals[1].first > 4);
}
