#include "TestUtils.h"
#include "VRXVALU.h"
#include "VRXVALU_RXVTypes.h"

struct ALUTestParams {
    uint32_t a;
    uint32_t b;
    uint32_t result;
    bool zero;
};

class RXVALUTest : public ::testing::Test
{
public:
    uint32_t add(uint32_t a, uint32_t b)
    {
        alu.a = a;
        alu.b = b;
        alu.op = alu.RXVTypes->ALU_ADD;

        alu.eval();

        return alu.q;
    }

    uint32_t sub(uint32_t a, uint32_t b)
    {
        alu.a = a;
        alu.b = b;
        alu.op = alu.RXVTypes->ALU_SUB;

        alu.eval();

        return alu.q;
    }

    uint32_t asr(uint32_t a, uint32_t b)
    {
        alu.a = a;
        alu.b = b;
        alu.op = alu.RXVTypes->ALU_SRA;

        alu.eval();

        return alu.q;
    }

    VRXVALU alu;
};

class AddFixture
    : public ::testing::WithParamInterface<ALUTestParams>
    , public RXVALUTest
{
};
TEST_P(AddFixture, Add)
{
    EXPECT_EQ(add(GetParam().a, GetParam().b), GetParam().result);
    EXPECT_EQ(GetParam().zero, alu.zero);
}
INSTANTIATE_TEST_CASE_P(AddSanity,
                        AddFixture,
                        ::testing::Values(ALUTestParams{0, 0, 0, true},
                                          ALUTestParams{0x7fffffff, 1,
                                                        0x80000000, false}));

class SubFixture
    : public ::testing::WithParamInterface<ALUTestParams>
    , public RXVALUTest
{
};
TEST_P(SubFixture, Sub)
{
    EXPECT_EQ(sub(GetParam().a, GetParam().b), GetParam().result);
    EXPECT_EQ(GetParam().zero, alu.zero);
}
INSTANTIATE_TEST_CASE_P(
    SubSanity,
    SubFixture,
    ::testing::Values(ALUTestParams{0, 0, 0, true},
                      ALUTestParams{0, 1, 0xffffffff, false},
                      ALUTestParams{0x80000000, 0x7fffffff, 1, false}));
class SRAFixture
    : public ::testing::WithParamInterface<ALUTestParams>
    , public RXVALUTest
{
};
TEST_P(SRAFixture, SRA)
{
    EXPECT_EQ(asr(GetParam().a, GetParam().b), GetParam().result);
}
INSTANTIATE_TEST_CASE_P(
    SraSanity,
    SRAFixture,
    ::testing::Values(ALUTestParams{0, 0, 0, true},
                      ALUTestParams{0x1, 1, 0, true},
                      ALUTestParams{0x7fffffff, 31, 0, false},
                      ALUTestParams{0x80000000, 31, 0xffffffff, false}));