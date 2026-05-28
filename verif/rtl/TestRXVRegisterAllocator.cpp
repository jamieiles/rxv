#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVRegisterAllocator.h"

template <typename T>
class RXVRegisterAllocatorTestBase
    : public T
    , public ::testing::Test
{
public:
    RXVRegisterAllocatorTestBase()
    {
        T::reset();
    }

    std::pair<bool, uint32_t> alloc()
    {
        T::after_n_cycles(0, [&] {
            this->dut.pop = 1;
            T::after_n_cycles(1, [&] { this->dut.pop = 0; });
        });
        T::cycle();
        return std::make_pair(this->dut.empty, this->dut.pop_reg);
    }

    void dealloc(int r)
    {
        T::after_n_cycles(0, [&] {
            this->dut.push = 1;
            this->dut.push_reg = r;
            T::after_n_cycles(1, [&] { this->dut.push = 0; });
        });
        T::cycle(2);
    }
};

class RXVRegisterAllocatorTest
    : public RXVRegisterAllocatorTestBase<
          VerilogTestbench<VRXVRegisterAllocator>>
{
};

class RXVRegisterAllocatorDeathTest
    : public RXVRegisterAllocatorTestBase<
          VerilogTestbench<VRXVRegisterAllocator, false>>
{
};

TEST_F(RXVRegisterAllocatorTest, AllocOne)
{
    auto reg = alloc();

    EXPECT_FALSE(reg.first);
    EXPECT_EQ(1, reg.second);
}

TEST_F(RXVRegisterAllocatorTest, Alloc48)
{
    for (int i = 1; i < 48; ++i) {
        auto reg = alloc();

        EXPECT_FALSE(reg.first);
        EXPECT_EQ(i, reg.second);
    }
    cycle();
    EXPECT_TRUE(this->dut.empty);
}

TEST_F(RXVRegisterAllocatorTest, AllocDealloc)
{
    for (int i = 1; i < 48; ++i) {
        auto reg = alloc();

        EXPECT_FALSE(reg.first);
        EXPECT_EQ(i, reg.second);
    }
    cycle();
    EXPECT_TRUE(this->dut.empty);

    for (int i = 47; i > 0; --i)
        dealloc(i);

    cycle();
    EXPECT_FALSE(this->dut.empty);
}

TEST_F(RXVRegisterAllocatorTest, AllocDeallocReverse)
{
    for (int i = 1; i < 48; ++i) {
        auto reg = alloc();

        EXPECT_FALSE(reg.first);
        EXPECT_EQ(i, reg.second);
    }
    cycle();
    EXPECT_TRUE(this->dut.empty);

    for (int i = 1; i < 48; ++i)
        dealloc(i);

    cycle();
    EXPECT_FALSE(this->dut.empty);
}

TEST_F(RXVRegisterAllocatorDeathTest, DoublePushFails)
{
    OutputSuprocessor stdout_suppress(STDOUT_FILENO);
    OutputSuprocessor stderr_suppress(STDERR_FILENO);
    GTEST_FLAG_SET(death_test_style, "threadsafe");

    EXPECT_EXIT(({
                    dealloc(1);
                    cycle();
                }),
                testing::ExitedWithCode(1), "");
}
