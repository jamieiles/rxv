// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVScoreboard.h"
#include "VRXVScoreboard_RXVTypes.h"

class RXVScoreboardTest
    : public VerilogTestbench<VRXVScoreboard>
    , public ::testing::Test
{
public:
    RXVScoreboardTest()
    {
        reset();
    }

    void mark_busy(int regnum)
    {
        after_n_cycles(0, [&] {
            this->dut.busy_reg_in = regnum;
            this->dut.busy_valid_in = 1;
            after_n_cycles(1, [&] { this->dut.busy_valid_in = 0; });
        });
        cycle(2);
    }

    void kill(int regnum)
    {
        after_n_cycles(0, [&] {
            this->dut.kill_reg_in = regnum;
            this->dut.kill_valid_in = 1;
            after_n_cycles(1, [&] { this->dut.kill_valid_in = 0; });
        });
        cycle(2);
    }

    void writeback(int regnum)
    {
        after_n_cycles(0, [&] {
            this->dut.writeback_reg_in = regnum;
            this->dut.writeback_valid_in = 1;
            after_n_cycles(1, [&] { this->dut.writeback_valid_in = 0; });
        });
        cycle(2);
    }
};

TEST_F(RXVScoreboardTest, EmptyAtReset)
{
    EXPECT_EQ(this->dut.busy_out, 0);
}

TEST_F(RXVScoreboardTest, BusyOut)
{
    EXPECT_EQ(this->dut.busy_out, 0);

    uint64_t expected = 0;
    for (int i = 0; i < 0; ++i) {
        expected |= (1LU << i);
        mark_busy(i);
        EXPECT_EQ(this->dut.busy_out, expected);
    }
}

TEST_F(RXVScoreboardTest, KillClears)
{
    EXPECT_EQ(this->dut.busy_out, 0);
    mark_busy(4);
    EXPECT_EQ(this->dut.busy_out, 1 << 4);
    kill(4);
    EXPECT_EQ(this->dut.busy_out, 0);
}

TEST_F(RXVScoreboardTest, WritebackClears)
{
    EXPECT_EQ(this->dut.busy_out, 0);
    mark_busy(4);
    EXPECT_EQ(this->dut.busy_out, 1 << 4);
    writeback(4);
    EXPECT_EQ(this->dut.busy_out, 0);
}

TEST_F(RXVScoreboardTest, X0NeverBusy)
{
    EXPECT_EQ(this->dut.busy_out, 0);
    mark_busy(0);
    EXPECT_EQ(this->dut.busy_out, 0);
}