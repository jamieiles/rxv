#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVScheduler.h"
#include "VRXVScheduler_RXVTypes.h"

class RXVSchedulerTest
    : public VerilogTestbench<VRXVScheduler>
    , public ::testing::Test
{
public:
    RXVSchedulerTest()
    {
        reset();
    }

    void dispatch_int()
    {
        after_n_cycles(0, [&] {
            this->dut.dispatch_int = 1;
            after_n_cycles(1, [&] { this->dut.dispatch_int = 0; });
        });
        cycle();
    }

    void dispatch_lsu()
    {
        after_n_cycles(0, [&] {
            this->dut.dispatch_lsu = 1;
            after_n_cycles(1, [&] { this->dut.dispatch_lsu = 0; });
        });
        cycle();
    }
};

TEST_F(RXVSchedulerTest, ReadyAtReset)
{
    EXPECT_TRUE(this->dut.int_ready);
    EXPECT_TRUE(this->dut.lsu_ready);
}

TEST_F(RXVSchedulerTest, IntPerCycle)
{
    for (int i = 0; i < 64; ++i) {
        dispatch_int();
        EXPECT_TRUE(this->dut.int_ready);
    }
}

TEST_F(RXVSchedulerTest, LSUPerCycle)
{
    for (int i = 0; i < 64; ++i) {
        dispatch_lsu();
        EXPECT_TRUE(this->dut.lsu_ready);
    }
}

TEST_F(RXVSchedulerTest, LSUInhibitsInt)
{
    dispatch_lsu();
    EXPECT_TRUE(this->dut.int_ready);
    cycle();
    EXPECT_TRUE(this->dut.int_ready);
    cycle();
    EXPECT_FALSE(this->dut.int_ready);
    EXPECT_TRUE(this->dut.lsu_ready);
}