// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <type_traits>

#include "TestUtils.h"
#include "VerilogTestbench.h"
#include "VRXVDiv.h"

class RXVDivTest
    : public VerilogTestbench<VRXVDiv>
    , public ::testing::Test
{
public:
    RXVDivTest()
    {
        reset();
    }

    template <typename T>
    std::pair<T, T> div(T dividend, T divisor)
    {
        after_n_cycles(0, [&] {
            this->dut.dividend = static_cast<uint32_t>(dividend);
            this->dut.divisor = static_cast<uint32_t>(divisor);
            this->dut.is_signed = std::is_signed<T>::value;
            this->dut.valid = 1;
            after_n_cycles(1, [&] {
                this->dut.dividend = 0;
                this->dut.divisor = 0;
                this->dut.is_signed = 0;
                this->dut.valid = 0;
            });
        });
        cycle(34);

        return std::make_pair(static_cast<T>(this->dut.quotient),
                              static_cast<T>(this->dut.remainder));
    }
};

TEST_F(RXVDivTest, SimpleDiv)
{
    uint32_t q, r;
    std::tie(q, r) = div<uint32_t>(9, 4);
    EXPECT_EQ(q, 2);
    EXPECT_EQ(r, 1);
}

class Div
    : public ::testing::WithParamInterface<
          std::tuple<int32_t, int32_t, int32_t, int32_t>>
    , public RXVDivTest
{
};
TEST_P(Div, SignedDivide)
{
    int32_t quotient, remainder;
    std::tie(quotient, remainder) =
        div<int32_t>(std::get<2>(GetParam()), std::get<3>(GetParam()));
    auto expected_quotient = std::get<0>(GetParam());
    auto expected_remainder = std::get<1>(GetParam());

    EXPECT_EQ(quotient, expected_quotient);
    EXPECT_EQ(remainder, expected_remainder);
}
INSTANTIATE_TEST_SUITE_P(
    SignedDiv,
    Div,
    ::testing::Values(
        std::make_tuple(-1, 0, 0, 0) /* Divide by zero */,
        std::make_tuple(INT32_MIN, 0, INT32_MIN, -1) /* Overflow */,
        std::make_tuple(4, 0, 4, 1),
        std::make_tuple(-4, 0, 4, -1),
        std::make_tuple(-4, 0, -4, 1),
        std::make_tuple(4, 0, -4, -1),
        std::make_tuple(-1, 2, 5, -3),
        std::make_tuple(1, 0, 0x100, 0x100),
        std::make_tuple(-1, -0x55555556, 0xaaaaaaaa, 0x0)));

class DivU
    : public ::testing::WithParamInterface<
          std::tuple<uint32_t, uint32_t, uint32_t, uint32_t>>
    , public RXVDivTest
{
};
TEST_P(DivU, UnsignedDivide)
{
    uint32_t quotient, remainder;
    std::tie(quotient, remainder) =
        div<uint32_t>(std::get<2>(GetParam()), std::get<3>(GetParam()));
    auto expected_quotient = std::get<0>(GetParam());
    auto expected_remainder = std::get<1>(GetParam());

    EXPECT_EQ(quotient, expected_quotient);
    EXPECT_EQ(remainder, expected_remainder);
}
INSTANTIATE_TEST_SUITE_P(
    UnsignedDiv,
    DivU,
    ::testing::Values(std::make_tuple(UINT32_MAX,
                                      UINT32_MAX,
                                      UINT32_MAX,
                                      0) /* Divide by zero */,
                      std::make_tuple(0x80000000, 0, 0x80000000, 1),
                      std::make_tuple(0x40000000, 0, 0x80000000, 2),
                      std::make_tuple(1, 0, 0x80000000, 0x80000000),
                      std::make_tuple(0x10, 0x10, 0x1000, 0xff),
                      std::make_tuple(0x0, 0x66666666, 0x66666666, 0xffbfffff),
                      std::make_tuple(0x0, 0x1, 0x1, 0x2)));