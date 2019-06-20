#include <iostream>
#include <vector>

#include "VerilogTestbench.h"
#include "VRXVCore.h"

struct RetiredInstruction {
    uint32_t insn;
    uint32_t pc;
    uint32_t next_pc;
    uint32_t rd_val;
    bool rd_written;
    uint8_t rd;
};

class RXVCoreTestbench
    : public VerilogTestbench<VRXVCore>
    , public ::testing::Test
{
public:
    static constexpr int num_instructions = 4096;

    RXVCoreTestbench()
    {
        reg_file_scope = svGetScopeFromName("TOP.RXVCore.RegFile");

        for (auto i = 0; i < num_instructions; ++i)
            instr_mem[i] = 0;

        periodic(ClockSetup, [&] {
            after_n_cycles(0, [&] {
                this->dut.i_data = this->instr_mem[this->dut.i_addr >> 2];
            });
        });
        periodic(ClockCapture, [&] {
            if (!this->dut.rvfi_valid)
                return;

            this->retired_instructions.emplace_back(RetiredInstruction{
                this->dut.rvfi_insn, this->dut.rvfi_pc_rdata,
                this->dut.rvfi_pc_wdata, this->dut.rvfi_rd_wdata,
                this->dut.verif_writeback, this->dut.rvfi_rd_addr});
        });
    }

    void write_reg(int r, int v)
    {
        svSetScope(reg_file_scope);
        this->dut.write_reg(r, v);
    }

    std::vector<RetiredInstruction> retired_instructions;
    uint32_t instr_mem[num_instructions];

private:
    svScope reg_file_scope;
};

TEST_F(RXVCoreTestbench, LUI)
{
    instr_mem[0] = 0;
    instr_mem[1] = 0xdeadb537;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(1, instr.rd_written);
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0xdeadb000, instr.rd_val);
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, AUIPC)
{
    instr_mem[0] = 0;
    // auipc x10, 0xeef
    instr_mem[1] = 0x00eef517;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(1, instr.rd_written);
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00eef004, instr.rd_val);
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, JAL)
{
    instr_mem[0] = 0;
    // jal x10, 0x100
    instr_mem[1] = 0x1000056f;
    instr_mem[2] = 0xdeadbeef;
    instr_mem[0x104 / 4] = 0x0100056f;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(1, instr.rd_written);
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00000008, instr.rd_val);
    EXPECT_EQ(0x104, instr.next_pc);

    instr = retired_instructions[1];
    EXPECT_EQ(0x104, instr.pc);
    EXPECT_NE(0xdeadbeef, instr.insn);
    EXPECT_EQ(0x0100056f, instr.insn);
    EXPECT_EQ(0x114, instr.next_pc);
    EXPECT_EQ(1, instr.rd_written);
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00000108, instr.rd_val);
}

TEST_F(RXVCoreTestbench, JALR)
{
    write_reg(2, 0x200);
    instr_mem[0] = 0;
    // jalr    x10,256(x2)
    instr_mem[1] = 0x10010567;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(1, instr.rd_written);
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00000008, instr.rd_val);
    EXPECT_EQ(256 + 0x200, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BEQTaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x200);
    instr_mem[0] = 0;
    // beq     x2,x3,c
    instr_mem[1] = 0x00310463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BEQNotTaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x201);
    instr_mem[0] = 0;
    // beq     x2,x3,c
    instr_mem[1] = 0x00310463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BNETaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x201);
    instr_mem[0] = 0;
    // bne     x2,x3,c
    instr_mem[1] = 0x00311463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BNENotTaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x200);
    instr_mem[0] = 0;
    // bne     x2,x3,c
    instr_mem[1] = 0x00311463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTTaken)
{
    write_reg(2, -2);
    write_reg(3, -1);
    instr_mem[0] = 0;
    // blt     x2,x3,c
    instr_mem[1] = 0x00314463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTNotTaken)
{
    write_reg(2, 1);
    write_reg(3, -1);
    instr_mem[0] = 0;
    // blt     x2,x3,c
    instr_mem[1] = 0x00314463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGETakenGreater)
{
    write_reg(2, 2);
    write_reg(3, 1);
    instr_mem[0] = 0;
    // bge     x2,x3,c
    instr_mem[1] = 0x00315463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGETakenEqual)
{
    write_reg(2, 2);
    write_reg(3, 2);
    instr_mem[0] = 0;
    // bge     x2,x3,c
    instr_mem[1] = 0x00315463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGENotTaken)
{
    write_reg(2, -2);
    write_reg(3, -1);
    instr_mem[0] = 0;
    // bge     x2,x3,c
    instr_mem[1] = 0x00315463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTUTaken)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // bltu     x2,x3,c
    instr_mem[1] = 0x00316463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTUNotTaken)
{
    write_reg(2, -2);
    write_reg(3, 2);
    instr_mem[0] = 0;
    // bltu     x2,x3,c
    instr_mem[1] = 0x00316463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGEUTakenGreater)
{
    write_reg(2, -1);
    write_reg(3, -2);
    instr_mem[0] = 0;
    // bgeu     x2,x3,c
    instr_mem[1] = 0x00317463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGEUTakenEqual)
{
    write_reg(2, 2);
    write_reg(3, 2);
    instr_mem[0] = 0;
    // bgeu     x2,x3,c
    instr_mem[1] = 0x00317463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGEUNotTaken)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // bgeu     x2,x3,c
    instr_mem[1] = 0x00317463;
    instr_mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
}