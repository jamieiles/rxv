#include "VerilogTestbench.h"
#include "VRXVFetchWrapper.h"

class RXVFetchTestBench
    : public VerilogTestbench<VRXVFetchWrapper>
    , public ::testing::Test
{
public:
    RXVFetchTestBench()
    {
        periodic(ClockCapture, [&] {
            if (!this->dut.icache_valid)
                return;
            auto addr = this->dut.icache_address;
            after_n_cycles(1, [this, addr] {
                this->dut.icache_instr = 0xffff0000 | addr;
            });
        });

        this->dut.icache_busy = 0;
        this->dut.icache_instr = 0;
        this->dut.branch_predict_valid = 0;
        this->dut.branch_prediction = 0;
        this->dut.branch_predict_taken = 0;
        this->dut.branch_predict_strength = 0;
        this->dut.decode_resteer = 0;
        this->dut.decode_resteer_tgt = 0;
        this->dut.decode_fe_stall = 0;
        this->dut.exec_resteer = 0;
        this->dut.exec_resteer_tgt = 0;

        reset();
    }
};

TEST_F(RXVFetchTestBench, IncrementingPC)
{
    for (int i = 0; i < 32; ++i) {
        if (this->dut.decode_valid)
            break;
        cycle();
    }
    EXPECT_TRUE(this->dut.decode_valid);

    auto last_pc = this->dut.decode_pc << 2;
    for (int i = 0; i < 4; ++i) {
        cycle();
        EXPECT_EQ(this->dut.decode_pc << 2, last_pc + 4);
        EXPECT_EQ(this->dut.decode_next_pc << 2,
                  (this->dut.decode_pc << 2) + 4);
        last_pc = this->dut.decode_pc << 2;
    }
    cycle(32);
}

TEST_F(RXVFetchTestBench, ICacheStall)
{
    cycle(16);
    after_n_cycles(0, [&] {
        this->dut.icache_busy = 1;
        after_n_cycles(3, [&] { this->dut.icache_busy = 0; });
    });

    auto last_fetch_addr = this->dut.icache_address;
    auto last_decode_addr = this->dut.decode_pc;
    EXPECT_TRUE(this->dut.decode_valid);
    cycle();

    for (int i = 0; i < 16; ++i) {
        if (this->dut.decode_valid) {
            EXPECT_EQ(this->dut.decode_pc, last_decode_addr + 1);
            last_decode_addr = this->dut.decode_pc;
        }
        last_fetch_addr = this->dut.icache_address;
        cycle();
    }
}

TEST_F(RXVFetchTestBench, Prediction)
{
    cycle(4);

    uint32_t last_pc = 0;
    for (int i = 0; i < 32; ++i) {
        if (this->dut.branch_predict_address == 0x20000008) {
            after_n_cycles(0, [&] {
                this->dut.branch_predict_valid = 1;
                this->dut.branch_predict_taken = 1;
                this->dut.branch_prediction = 0x80004444 >> 2;
                after_n_cycles(1, [&] { this->dut.branch_predict_valid = 0; });
            });
        }

        if (last_pc == 0x20000008 && this->dut.decode_valid) {
            EXPECT_EQ(this->dut.decode_pc, 0x80004444 >> 2);
            break;
        }

        if (this->dut.decode_valid)
            last_pc = this->dut.decode_pc;

        if (i == 31)
            FAIL() << "never saw resteer";

        cycle();
    }
    cycle(8);
}

TEST_F(RXVFetchTestBench, BranchResolution)
{
    cycle(4);

    uint32_t last_pc = 0;
    for (int i = 0; i < 32; ++i) {
        if (this->dut.decode_pc == 0x20000007) {
            after_n_cycles(0, [&] {
                this->dut.exec_resteer = 1;
                this->dut.exec_resteer_tgt = 0x80004444 >> 2;
                after_n_cycles(1, [&] { this->dut.exec_resteer = 0; });
            });
        }

        if (last_pc == 0x20000008 && this->dut.decode_valid) {
            EXPECT_EQ(this->dut.decode_pc, 0x80004444 >> 2);
            break;
        }

        if (this->dut.decode_valid)
            last_pc = this->dut.decode_pc;

        if (i == 31)
            FAIL() << "never saw resteer";

        cycle();
    }
    cycle(8);
}

class RXVFetchLineFill
    : public ::testing::WithParamInterface<int>
    , public RXVFetchTestBench
{
};

TEST_P(RXVFetchLineFill, ResteerDuringLineFill)
{
    cycle(4);

    after_n_cycles(4, [&] { this->dut.icache_busy = 1; });
    after_n_cycles(3 + GetParam(), [&] {
        this->dut.exec_resteer = 1;
        this->dut.exec_resteer_tgt = 0x80004444 >> 2;
        after_n_cycles(1, [&] {
            this->dut.exec_resteer = 0;
            this->dut.exec_resteer_tgt = 0;
        });
    });
    cycle(5);

    for (int i = 0; i < 8; ++i) {
        if (this->dut.decode_valid)
            EXPECT_LT(this->dut.decode_pc, 0x80000100 >> 2);
        cycle();
    }
    EXPECT_FALSE(this->dut.decode_valid);

    after_n_cycles(0, [&] { this->dut.icache_busy = 0; });

    for (int i = 0; i < 8; ++i) {
        if (this->dut.decode_valid) {
            EXPECT_EQ(this->dut.decode_pc, 0x80004444 >> 2);
            break;
        }

        if (i == 7)
            FAIL() << "stall never ended";
        cycle();
    }
    cycle(8);
}
INSTANTIATE_TEST_CASE_P(ResteerLineFillLatency,
                        RXVFetchLineFill,
                        ::testing::Values(0, 1, 2, 3));
