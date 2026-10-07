// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <gtest/gtest.h>
#include <VPLIC.h>

#include "VerilogTestbench.h"

namespace
{
const uint32_t PENDING = 0x001000;
const uint32_t ENABLE = 0x002000;
const uint32_t THRESHOLD = 0x200000;
const uint32_t CLAIM = 0x200004;

const int CTX_M = 0;
const int CTX_S = 1;
} // namespace

class PLICTestbench : public VerilogTestbench<VPLIC>, public ::testing::Test
{
public:
    PLICTestbench()
    {
        dut.sources = 0;
        dut.reg_wr = 0;
        dut.reg_rd = 0;
        reset();
    }

    void write(uint32_t addr, uint32_t v)
    {
        dut.reg_waddr = addr;
        dut.reg_wdata = v;
        dut.reg_wstrb = 0xf;
        dut.reg_wr = 1;
        cycle();
        dut.reg_wr = 0;
    }

    uint32_t read(uint32_t addr)
    {
        dut.reg_raddr = addr;
        dut.reg_rd = 1;
        dut.eval();
        uint32_t v = dut.reg_rdata;
        cycle();
        dut.reg_rd = 0;
        return v;
    }

    uint32_t claim(int ctx)
    {
        return read(CLAIM + ctx * 0x1000);
    }

    void complete(int ctx, uint32_t id)
    {
        write(CLAIM + ctx * 0x1000, id);
    }

    void set_source(int id, bool level)
    {
        if (level)
            dut.sources |= 1 << (id - 1);
        else
            dut.sources &= ~(1 << (id - 1));
        cycle();
    }

    bool irq(int ctx)
    {
        dut.eval();
        return dut.irq & (1 << ctx);
    }
};

TEST_F(PLICTestbench, RegistersReadBack)
{
    write(4 * 1, 7);
    write(4 * 3, 2);
    write(ENABLE + CTX_S * 0x80, 0xe);
    write(THRESHOLD + CTX_S * 0x1000, 3);

    EXPECT_EQ(read(4 * 1), 7u);
    EXPECT_EQ(read(4 * 2), 0u);
    EXPECT_EQ(read(4 * 3), 2u);
    EXPECT_EQ(read(ENABLE + CTX_S * 0x80), 0xeu);
    EXPECT_EQ(read(ENABLE + CTX_M * 0x80), 0u);
    EXPECT_EQ(read(THRESHOLD + CTX_S * 0x1000), 3u);
}

TEST_F(PLICTestbench, DisabledOrZeroPriorityDoesNotInterrupt)
{
    set_source(1, true);
    EXPECT_EQ(read(PENDING), 0x2u);
    EXPECT_FALSE(irq(CTX_S));

    // Enabled with priority zero
    write(ENABLE + CTX_S * 0x80, 0x2);
    EXPECT_FALSE(irq(CTX_S));

    write(4 * 1, 1);
    cycle();
    EXPECT_TRUE(irq(CTX_S));
    EXPECT_FALSE(irq(CTX_M));
}

TEST_F(PLICTestbench, ClaimComplete)
{
    write(4 * 2, 1);
    write(ENABLE + CTX_S * 0x80, 0x4);
    set_source(2, true);
    EXPECT_TRUE(irq(CTX_S));

    EXPECT_EQ(claim(CTX_S), 2u);
    cycle();
    // Claimed: no longer pending even though the level is high.
    EXPECT_FALSE(irq(CTX_S));
    EXPECT_EQ(read(PENDING), 0u);
    EXPECT_EQ(claim(CTX_S), 0u);

    // The source is still asserted so it is pending again on completion.
    complete(CTX_S, 2);
    cycle(2);
    EXPECT_TRUE(irq(CTX_S));

    EXPECT_EQ(claim(CTX_S), 2u);
    set_source(2, false);
    complete(CTX_S, 2);
    cycle(2);
    EXPECT_FALSE(irq(CTX_S));
}

TEST_F(PLICTestbench, PriorityAndThreshold)
{
    write(4 * 1, 2);
    write(4 * 2, 5);
    write(4 * 3, 5);
    write(ENABLE + CTX_S * 0x80, 0xe);
    set_source(1, true);
    set_source(2, true);
    set_source(3, true);

    // Highest priority first, the lowest ID wins a tie.
    EXPECT_EQ(claim(CTX_S), 2u);
    EXPECT_EQ(claim(CTX_S), 3u);
    EXPECT_EQ(claim(CTX_S), 1u);
    EXPECT_EQ(claim(CTX_S), 0u);
    complete(CTX_S, 1);
    complete(CTX_S, 2);
    complete(CTX_S, 3);
    cycle(2);

    // Only priorities above the threshold interrupt.
    write(THRESHOLD + CTX_S * 0x1000, 5);
    cycle();
    EXPECT_FALSE(irq(CTX_S));
    write(THRESHOLD + CTX_S * 0x1000, 4);
    cycle();
    EXPECT_TRUE(irq(CTX_S));
}

TEST_F(PLICTestbench, ContextsAreIndependent)
{
    write(4 * 1, 1);
    write(4 * 3, 1);
    write(ENABLE + CTX_M * 0x80, 0x2);
    write(ENABLE + CTX_S * 0x80, 0x8);
    set_source(1, true);
    EXPECT_TRUE(irq(CTX_M));
    EXPECT_FALSE(irq(CTX_S));

    set_source(3, true);
    EXPECT_TRUE(irq(CTX_S));
    EXPECT_EQ(claim(CTX_S), 3u);
    EXPECT_EQ(claim(CTX_M), 1u);

    // Completing an ID not enabled for the context is ignored.
    complete(CTX_M, 3);
    cycle(2);
    EXPECT_EQ(claim(CTX_S), 0u);
    complete(CTX_S, 3);
    cycle(2);
    EXPECT_EQ(claim(CTX_S), 3u);
}
