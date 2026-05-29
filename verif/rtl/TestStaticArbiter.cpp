// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <gtest/gtest.h>
#include <VStaticArbiter.h>

#include "VerilogTestbench.h"

class StaticArbiterTestFixture
    : public VerilogTestbench<VStaticArbiter>
    , public ::testing::Test
{
public:
    StaticArbiterTestFixture()
    {
        reset();
    }
};

TEST_F(StaticArbiterTestFixture, MultipleReqs)
{
    this->dut.request = 0xf;
    cycle();
    EXPECT_EQ(this->dut.grant, 1);
}

TEST_F(StaticArbiterTestFixture, CombinationalOut)
{
    this->dut.request = 0xf;
    EXPECT_EQ(this->dut.grant, 0);
    this->dut.eval();
    EXPECT_EQ(this->dut.grant, 1);
}

TEST_F(StaticArbiterTestFixture, GrantHold)
{
    after_n_cycles(0, [&] {
        this->dut.request = 0xf;
        after_n_cycles(1, [&] {
            this->dut.request = 0;
            this->dut.hold = 1;
        });
    });
    cycle(2);

    for (int i = 0; i < 10; ++i) {
        EXPECT_EQ(this->dut.grant, 1);
        EXPECT_EQ(this->dut.request, 0);
        cycle();
    }

    after_n_cycles(0, [&] { this->dut.hold = 0; });
    cycle();

    EXPECT_EQ(this->dut.grant, 0);
}

TEST_F(StaticArbiterTestFixture, NoChangeDuringHold)
{
    after_n_cycles(0, [&] {
        this->dut.request = 0xf;
        after_n_cycles(1, [&] {
            this->dut.request = 0;
            this->dut.hold = 1;
        });
    });
    cycle(2);

    for (int i = 0; i < 10; ++i) {
        after_n_cycles(0, [&] { this->dut.request++; });
        EXPECT_EQ(this->dut.grant, 1);
        cycle();
    }

    after_n_cycles(0, [&] {
        this->dut.hold = 0;
        this->dut.request = 0;
    });
    cycle();

    EXPECT_EQ(this->dut.grant, 0);
}