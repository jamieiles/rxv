#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVRenameFileWrapper.h"

class RXVRenameFileTest
    : public VerilogTestbench<VRXVRenameFileWrapper>
    , public ::testing::Test
{
public:
    RXVRenameFileTest()
    {
        reset();
    }

    // Returns stale physical reg
    int rename(int arch, int phys)
    {
        int stale;
        after_n_cycles(0, [&] {
            this->dut.rename_valid = 1;
            this->dut.rename_in_arch = arch;
            this->dut.rename_in_phys = phys;
            this->dut.eval();
            stale = this->dut.stale_phys_reg;
            after_n_cycles(1, [&] { this->dut.rename_valid = 0; });
        });
        cycle(2);
        return stale;
    }

    void commit(int arch, int phys)
    {
        after_n_cycles(0, [&] {
            this->dut.commit_in_arch = arch;
            this->dut.commit_in_phys = phys;
            this->dut.commit_valid = 1;
            after_n_cycles(1, [&] { this->dut.commit_valid = 0; });
        });
        cycle(2);
    }

    void rollback()
    {
        after_n_cycles(0, [&] {
            this->dut.rollback = 1;
            after_n_cycles(1, [&] { this->dut.rollback = 0; });
        });
        cycle(2);
    }
};

TEST_F(RXVRenameFileTest, ResetAllRegsMappedZero)
{
    for (auto i = 0; i < 32; ++i) {
        this->dut.rename_in_arch = i;
        this->dut.eval();
        EXPECT_EQ(this->dut.stale_phys_reg, 0);
    }
}

TEST_F(RXVRenameFileTest, RenameAll)
{
    for (auto i = 0; i < 32; ++i)
        EXPECT_EQ(rename(i, i + 1), 0);

    for (auto i = 0; i < 16; ++i) {
        this->dut.lookup_tag_in[0] = i * 2;
        this->dut.lookup_tag_in[1] = i * 2 + 1;
        this->dut.eval();
        EXPECT_EQ(this->dut.lookup_tag_out[0], i * 2 + 1);
        EXPECT_EQ(this->dut.lookup_tag_out[1], i * 2 + 2);
    }
}

TEST_F(RXVRenameFileTest, Rollback)
{
    for (auto i = 0; i < 32; ++i)
        EXPECT_EQ(rename(i, i + 1), 0);

    rollback();

    for (auto i = 0; i < 16; ++i) {
        this->dut.lookup_tag_in[0] = i * 2;
        this->dut.lookup_tag_in[1] = i * 2 + 1;
        this->dut.eval();
        EXPECT_EQ(this->dut.lookup_tag_out[0], 0);
        EXPECT_EQ(this->dut.lookup_tag_out[1], 0);
    }
}

TEST_F(RXVRenameFileTest, CommitRollback)
{
    for (auto i = 0; i < 32; ++i)
        EXPECT_EQ(rename(i, i + 1), 0);

    for (auto i = 0; i < 32; ++i)
        commit(i, i + 1);

    for (auto i = 0; i < 32; ++i)
        EXPECT_EQ(rename(i, i + 3), i + 1);

    rollback();

    for (auto i = 0; i < 16; ++i) {
        this->dut.lookup_tag_in[0] = i * 2;
        this->dut.lookup_tag_in[1] = i * 2 + 1;
        this->dut.eval();
        EXPECT_EQ(this->dut.lookup_tag_out[0], i * 2 + 1);
        EXPECT_EQ(this->dut.lookup_tag_out[1], i * 2 + 2);
    }
}