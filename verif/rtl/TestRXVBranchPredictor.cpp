// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVBranchPredictorWrapper.h"

template <typename T = int32_t>
static T sign_extend(uint32_t u, int bits)
{
    T s = static_cast<T>(u);

    s <<= (sizeof(T) * 8) - bits;
    s >>= (sizeof(T) * 8) - bits;

    return s;
}

class RXVBranchPredictorTest
    : public VerilogTestbench<VRXVBranchPredictorWrapper>
    , public ::testing::Test
{
public:
    RXVBranchPredictorTest()
    {
        reset();
    }

    struct Prediction {
        bool valid;
        bool taken;
        int8_t strength;
        uint32_t prediction;
    };

    Prediction fetch(uint32_t addr)
    {
        after_n_cycles(0, [&] {
            this->dut.fetch_address = addr >> 2;
            after_n_cycles(1, [&] { this->dut.fetch_address = 0; });
        });
        cycle(2);

        return Prediction{
            !!this->dut.fetch_prediction_valid, !!this->dut.fetch_predict_taken,
            sign_extend<int8_t>(this->dut.fetch_predict_strength, 2),
            this->dut.fetch_prediction};
    }

    void update(uint32_t addr,
                uint32_t target,
                int8_t prev_strength,
                bool taken)
    {
        after_n_cycles(0, [&] {
            this->dut.exec_predict_address = addr >> 2;
            this->dut.exec_predict_target = target >> 2;
            this->dut.exec_predict_taken = taken;
            this->dut.exec_predict_prev_strength = prev_strength;
            this->dut.exec_predict_update = 1;
            after_n_cycles(1, [&] { this->dut.exec_predict_update = 0; });
        });
        cycle(2);
    }

    void decode_kill(uint32_t addr)
    {
        after_n_cycles(0, [&] {
            this->dut.decode_kill_address = addr >> 2;
            this->dut.decode_predict_kill = 1;
            after_n_cycles(1, [&] { this->dut.decode_predict_kill = 0; });
        });
        cycle(2);
    }
};

TEST_F(RXVBranchPredictorTest, EmptyNoPredict)
{
    for (uint32_t i = 0x8000; i < 0x8020; ++i) {
        auto p = fetch(i);
        EXPECT_FALSE(p.valid);
        EXPECT_FALSE(p.taken);
    }
}

TEST_F(RXVBranchPredictorTest, PredictionStrength)
{
    auto p = fetch(0x8000);
    EXPECT_FALSE(p.valid);
    EXPECT_FALSE(p.taken);

    update(0x8000, 0x9090, 0, true);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_TRUE(p.taken);
    EXPECT_EQ(1, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);

    update(0x8000, 0x9090, 1, true);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_TRUE(p.taken);
    EXPECT_EQ(1, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);

    update(0x8000, 0x9090, 1, false);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_TRUE(p.taken);
    EXPECT_EQ(0, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);

    update(0x8000, 0x9090, 0, false);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_FALSE(p.taken);
    EXPECT_EQ(-1, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);

    update(0x8000, 0x9090, -1, false);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_FALSE(p.taken);
    EXPECT_EQ(-2, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);

    update(0x8000, 0x9090, -2, false);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_FALSE(p.taken);
    EXPECT_EQ(-2, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);
}

TEST_F(RXVBranchPredictorTest, DecodeKill)
{
    auto p = fetch(0x8000);
    EXPECT_FALSE(p.valid);
    EXPECT_FALSE(p.taken);

    update(0x8000, 0x9090, 0, true);
    p = fetch(0x8000);
    EXPECT_TRUE(p.valid);
    EXPECT_TRUE(p.taken);
    EXPECT_EQ(1, p.strength);
    EXPECT_EQ(0x9090, p.prediction << 2);

    decode_kill(0x8000);

    p = fetch(0x8000);
    EXPECT_FALSE(p.valid);
}