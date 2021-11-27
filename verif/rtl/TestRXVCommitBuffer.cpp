#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVCommitBuffer.h"
#include "VRXVCommitBuffer_RXVTypes.h"

class RXVCommitBufferTest
    : public VerilogTestbench<VRXVCommitBuffer>
    , public ::testing::Test
{
public:
    struct CommitEntry {
        uint8_t stale_phys;
        uint8_t dest_arch;
        uint8_t dest_phys;
        uint32_t pc;
        bool have_writeback;
        bool complete;
        bool killed;
        bool excepted;
    };

    RXVCommitBufferTest()
    {
        reset();
    }

    uint8_t dispatch(uint8_t stale_phys_reg,
                     uint8_t renamed_arch,
                     uint8_t renamed_phys,
                     uint32_t pc,
                     bool have_writeback)
    {
        uint8_t dispatch_id;
        auto commit_entry = this->dut.RXVTypes->make_commit_entry(
            stale_phys_reg, renamed_arch, renamed_phys, pc, have_writeback);
        after_n_cycles(0, [&] {
            this->dut.dispatch_in = commit_entry;
            this->dut.dispatch_valid = 1;
            dispatch_id = this->dut.dispatch_id;
            after_n_cycles(1, [&] { this->dut.dispatch_valid = 0; });
        });
        cycle(2);

        return dispatch_id;
    }

    CommitEntry commit(void)
    {
        CommitEntry ce;

        after_n_cycles(0, [&] {
            auto rtl_ce = this->dut.commit_out;
            ce.stale_phys = this->dut.RXVTypes->commit_entry_stale(rtl_ce);
            ce.dest_arch = this->dut.RXVTypes->commit_entry_dest_arch(rtl_ce);
            ce.dest_phys = this->dut.RXVTypes->commit_entry_dest_phys(rtl_ce);
            ce.pc = this->dut.RXVTypes->commit_entry_pc(rtl_ce);
            ce.have_writeback =
                this->dut.RXVTypes->commit_entry_have_writeback(rtl_ce);
            ce.complete = this->dut.commit_complete_out;
            ce.killed = this->dut.commit_killed_out;
            ce.excepted = this->dut.commit_excepted_out;
            this->dut.commit_valid = 1;
            after_n_cycles(1, [&] { this->dut.commit_valid = 0; });
        });
        cycle(2);

        return ce;
    }

    void except(uint8_t id)
    {
        after_n_cycles(0, [&] {
            this->dut.except_id = id;
            this->dut.except_valid = 1;
            after_n_cycles(1, [&] { this->dut.except_valid = 0; });
        });
        cycle(2);
    }

    void kill(uint8_t id)
    {
        after_n_cycles(0, [&] {
            this->dut.kill_id = id;
            this->dut.kill_valid = 1;
            after_n_cycles(1, [&] { this->dut.kill_valid = 0; });
        });
        cycle(2);
    }
};

TEST_F(RXVCommitBufferTest, EmptyAtReset)
{
    EXPECT_TRUE(this->dut.empty);
    EXPECT_FALSE(this->dut.commit_complete_out);
    EXPECT_FALSE(this->dut.commit_killed_out);
    EXPECT_FALSE(this->dut.commit_excepted_out);
}

TEST_F(RXVCommitBufferTest, DispatchIncrementingID)
{
    for (int i = 0; i < 7; ++i) {
        auto id = dispatch(i, i + 8, i + 16, 0x80001000 + i, 1);
        EXPECT_EQ(id, i);
    }
}

TEST_F(RXVCommitBufferTest, Except)
{
    EXPECT_FALSE(this->dut.commit_excepted_out);

    auto id = dispatch(0, 8, 16, 0x80001000, 1);
    EXPECT_EQ(id, 0);

    except(id);

    EXPECT_TRUE(this->dut.commit_excepted_out);
}

TEST_F(RXVCommitBufferTest, CommitOrder)
{
    for (int i = 0; i < 7; ++i) {
        auto id = dispatch(i, i + 8, i + 16, (0x80001000 >> 2) + i, 1);
        EXPECT_EQ(id, i);
    }

    for (int i = 0; i < 7; ++i) {
        auto ce = commit();
        EXPECT_EQ(ce.pc, (0x80001000 >> 2) + i);
    }
}

TEST_F(RXVCommitBufferTest, Kill)
{
    for (int i = 0; i < 7; ++i) {
        auto id = dispatch(i, i + 8, i + 16, (0x80001000 >> 2) + i, 1);
        EXPECT_EQ(id, i);
    }

    except(2);
    kill(4);

    for (int i = 0; i < 7; ++i) {
        auto ce = commit();

        if (i == 2)
            EXPECT_TRUE(ce.excepted);
        else
            EXPECT_FALSE(ce.excepted);

        if (i >= 2 && i <= 4)
            EXPECT_TRUE(ce.killed);
        else
            EXPECT_FALSE(ce.killed);
    }

    cycle();
}

TEST_F(RXVCommitBufferTest, KillWithoutExcept)
{
    for (int i = 0; i < 7; ++i) {
        auto id = dispatch(i, i + 8, i + 16, (0x80001000 >> 2) + i, 1);
        EXPECT_EQ(id, i);
    }

    kill(4);

    for (int i = 0; i < 7; ++i) {
        auto ce = commit();

        EXPECT_FALSE(ce.excepted);

        if (i == 4)
            EXPECT_TRUE(ce.killed);
        else
            EXPECT_FALSE(ce.killed);
    }

    cycle();
}

TEST_F(RXVCommitBufferTest, EmptyDrainsException)
{
    for (int i = 0; i < 7; ++i) {
        auto id = dispatch(i, i + 8, i + 16, (0x80001000 >> 2) + i, 1);
        EXPECT_EQ(id, i);
    }

    except(2);
    kill(4);

    for (int i = 0; i < 7; ++i)
        commit();

    EXPECT_TRUE(this->dut.empty);
    EXPECT_FALSE(this->dut.commit_excepted_out);
    EXPECT_FALSE(this->dut.commit_killed_out);

    cycle();
    EXPECT_TRUE(this->dut.empty);

    dispatch(0, 8, 16, 0x80001000 >> 2, 1);
    EXPECT_FALSE(this->dut.commit_excepted_out);
    EXPECT_FALSE(this->dut.commit_killed_out);

    auto ce = commit();
    EXPECT_FALSE(ce.excepted);
    EXPECT_FALSE(ce.killed);

    cycle();
}