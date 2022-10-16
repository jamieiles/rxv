#include "VerilogTestbench.h"
#include "VRXVPMP.h"
#include "RXVSim.h"

#include <fmt/core.h>

class PMPTestbench
    : public VerilogTestbench<VRXVPMP>
    , public ::testing::Test
{
public:
    PMPTestbench()
    {
    }

    void set_addr(int idx, uint32_t data)
    {
        after_n_cycles(0, [&] {
            this->dut.update_addr_idx = idx;
            this->dut.update_addr = 1;
            this->dut.update_data = data;
            after_n_cycles(1, [&] { this->dut.update_addr = 0; });
        });
        cycle(2);
    }

    void set_config(uint32_t data)
    {
        after_n_cycles(0, [&] {
            this->dut.update_cfg = 1;
            this->dut.update_data = data;
            after_n_cycles(1, [&] { this->dut.update_cfg = 0; });
        });
        cycle(2);
    }

    uint8_t data_perms(uint32_t addr)
    {
        this->dut.data_addr = addr >> 2;
        this->dut.eval();

        return this->dut.data_perms;
    }

    uint8_t instr_perms(uint32_t addr)
    {
        this->dut.instr_addr = addr >> 2;
        this->dut.eval();

        return this->dut.instr_perms;
    }
};

TEST_F(PMPTestbench, Perms)
{
    set_addr(0, 0x3c001fff);
    set_addr(1, 0x20007fff);
    set_addr(2, 0xffffffff);
    set_addr(3, 0x00000000);
    set_config(0x001f1818);

    cycle(4);

    EXPECT_EQ(7, instr_perms(0x7ffffffc));
    EXPECT_EQ(0, instr_perms(0x80000000));
    EXPECT_EQ(0, instr_perms(0x8003fffc));
    EXPECT_EQ(7, instr_perms(0x80040000));

    EXPECT_EQ(7, data_perms(0x7ffffffc));
    EXPECT_EQ(0, data_perms(0x80000000));
    EXPECT_EQ(0, data_perms(0x8003fffc));
    EXPECT_EQ(7, data_perms(0x80040000));
}
