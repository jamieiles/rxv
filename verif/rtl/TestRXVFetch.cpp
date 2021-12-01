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
        this->dut.decode_stall = 0;
        this->dut.decode_resume_tgt = 0;
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

TEST_F(RXVFetchTestBench, DecodeStall)
{
    uint32_t stall_pc;

    cycle(4);
    after_n_cycles(0, [&] {
        this->dut.decode_stall = 1;
        stall_pc = this->dut.decode_resume_tgt = this->dut.decode_next_pc;
    });
    cycle();

    for (int i = 0; i < 4; ++i) {
        cycle();
        EXPECT_EQ(this->dut.icache_address, stall_pc);
        EXPECT_FALSE(this->dut.icache_valid);
    }
    after_n_cycles(0, [&] { this->dut.decode_stall = 0; });

    for (int i = 0; i < 4; ++i) {
        if (this->dut.icache_valid) {
            EXPECT_EQ(this->dut.icache_address, stall_pc);
            break;
        }

        if (i == 3)
            FAIL() << "stall not exited";
        cycle();
    }

    cycle(8);
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

TEST_F(RXVFetchTestBench, StallDuringLineFill)
{
    cycle();
    after_n_cycles(0, [&] { this->dut.decode_stall = 1; });
    cycle();

    for (int i = 0; i < 256; ++i) {
        cycle();
        ASSERT_FALSE(this->dut.decode_valid);
    }
}

TEST_F(RXVFetchTestBench, ResteerDuringLineFill)
{
    cycle(4);

    after_n_cycles(0, [&] { this->dut.icache_busy = 1; });
    cycle(4);
    ASSERT_TRUE(this->dut.icache_busy);

    after_n_cycles(4, [&] {
        this->dut.exec_resteer = 1;
        this->dut.exec_resteer_tgt = 0x80004444 >> 2;
        after_n_cycles(1, [&] {
            this->dut.exec_resteer = 0;
            this->dut.exec_resteer_tgt = 0;
        });
    });

    for (int i = 0; i < 8; ++i) {
        EXPECT_FALSE(this->dut.decode_valid);
        cycle();
    }
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