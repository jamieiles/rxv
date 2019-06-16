#include <gtest/gtest.h>
#include "VerilogTestbench.h"
#include "VRegFile.h"

double cur_time_stamp = 0;

class RegFileTestbench
    : public VerilogTestbench<VRegFile>
    , public ::testing::Test
{
};

TEST_F(RegFileTestbench, clocks)
{
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
    cycle();
}

int main(int argc, char *argv[])
{
    ::testing::InitGoogleTest(&argc, argv);

    return RUN_ALL_TESTS();
}
