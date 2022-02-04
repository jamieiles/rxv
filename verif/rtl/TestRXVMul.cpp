#include <type_traits>

#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVMul.h"

class RXVMulTest
    : public VerilogTestbench<VRXVMul>
    , public ::testing::Test
{
public:
    RXVMulTest()
    {
        reset();
    }

    template <typename Q, typename A, typename B>
    Q mul(A a, B b)
    {
        after_n_cycles(0, [&] {
            this->dut.a = static_cast<uint32_t>(a);
            this->dut.signed_a = std::is_signed<A>::value;
            this->dut.b = static_cast<uint32_t>(b);
            this->dut.signed_b = std::is_signed<B>::value;
        });
        cycle(5);

        return static_cast<Q>(this->dut.q);
    }

    void dispatch(int32_t a, int32_t b)
    {
        after_n_cycles(0, [&] {
            this->dut.a = a;
            this->dut.signed_a = 1;
            this->dut.b = b;
            this->dut.signed_b = 1;
        });
        cycle();
    }
};

TEST_F(RXVMulTest, PipelinedMul)
{
    dispatch(2, 4);
    dispatch(3, 3);

    cycle(3);
    EXPECT_EQ(this->dut.q, 8);
    cycle();
    EXPECT_EQ(this->dut.q, 9);
}

class MulSS
    : public ::testing::WithParamInterface<
          std::tuple<int64_t, int32_t, int32_t>>
    , public RXVMulTest
{
};
TEST_P(MulSS, SignedMultiply)
{
    auto result = mul<int64_t, int32_t, int32_t>(std::get<1>(GetParam()),
                                                 std::get<2>(GetParam()));
    auto expected = std::get<0>(GetParam());
    EXPECT_EQ(result, expected);
}
INSTANTIATE_TEST_SUITE_P(SignedMultiply,
                        MulSS,
                        ::testing::Values(std::make_tuple(0, 0, 0),
                                          std::make_tuple(0, 1, 0),
                                          std::make_tuple(1, 1, 1),
                                          std::make_tuple(2, 1, 2),
                                          std::make_tuple(8, 4, 2),
                                          std::make_tuple(-1, 1, -1),
                                          std::make_tuple(1, -1, -1)));

class MulSU
    : public ::testing::WithParamInterface<
          std::tuple<int64_t, int32_t, uint32_t>>
    , public RXVMulTest
{
};
TEST_P(MulSU, SignedUnsignedMultiply)
{
    auto result = mul<int64_t, int32_t, uint32_t>(std::get<1>(GetParam()),
                                                  std::get<2>(GetParam()));
    auto expected = std::get<0>(GetParam());
    EXPECT_EQ(result, expected);
}
INSTANTIATE_TEST_SUITE_P(
    SignedUnsignedMultiply,
    MulSU,
    ::testing::Values(std::make_tuple(0, 0, 0),
                      std::make_tuple(0, 1, 0),
                      std::make_tuple(1, 1, 1),
                      std::make_tuple(2, 1, 2),
                      std::make_tuple(8, 4, 2),
                      std::make_tuple(-1, -1, 1),
                      std::make_tuple(-4, -1, 4),
                      std::make_tuple(0x100000000, 2, 0x80000000)));

class MulUU
    : public ::testing::WithParamInterface<
          std::tuple<int64_t, uint32_t, uint32_t>>
    , public RXVMulTest
{
};
TEST_P(MulUU, UnsignedUnsignedMultiply)
{
    auto result = mul<uint64_t, uint32_t, uint32_t>(std::get<1>(GetParam()),
                                                    std::get<2>(GetParam()));
    auto expected = std::get<0>(GetParam());
    EXPECT_EQ(result, expected);
}
INSTANTIATE_TEST_SUITE_P(
    UnsignedUnsignedMultiply,
    MulUU,
    ::testing::Values(
        std::make_tuple(0, 0, 0),
        std::make_tuple(0, 1, 0),
        std::make_tuple(1, 1, 1),
        std::make_tuple(2, 1, 2),
        std::make_tuple(8, 4, 2),
        std::make_tuple(0xffffffff, 0xffffffff, 1),
        std::make_tuple(0xfffffffe00000001, 0xffffffff, 0xffffffff),
        std::make_tuple(0x100000000, 2, 0x80000000)));