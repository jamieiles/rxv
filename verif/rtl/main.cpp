#include <gtest/gtest.h>

double cur_time_stamp = 0;

double sc_time_stamp()
{
    return cur_time_stamp;
}

int main(int argc, char *argv[])
{
    ::testing::InitGoogleTest(&argc, argv);

    return RUN_ALL_TESTS();
}
