#include <iostream>
#include <vector>

#include "VerilogTestbench.h"
#include "VRXVCore.h"

struct RetiredInstruction {
    uint32_t insn;
    uint32_t pc;
    uint32_t next_pc;
    uint32_t rd_val;
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
                this->dut.rvfi_rd_addr});
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
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00000008, instr.rd_val);
    EXPECT_EQ(0x104, instr.next_pc);

    instr = retired_instructions[1];
    EXPECT_EQ(0x104, instr.pc);
    EXPECT_NE(0xdeadbeef, instr.insn);
    EXPECT_EQ(0x0100056f, instr.insn);
    EXPECT_EQ(0x114, instr.next_pc);
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

// Register-Register Arithmetic

TEST_F(RXVCoreTestbench, ADD)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // add     x1,x2,x3
    instr_mem[1] = 0x003100b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(5, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SUB)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // sub     x1,x2,x3
    instr_mem[1] = 0x403100b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xffffffff, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLL)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // sll     x1,x2,x3
    instr_mem[1] = 0x003110b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2 << 3, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTLess)
{
    write_reg(2, -2);
    write_reg(3, -1);
    instr_mem[0] = 0;
    // slt     x1,x2,x3
    instr_mem[1] = 0x003120b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTNotLess)
{
    write_reg(2, 4);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // slt     x1,x2,x3
    instr_mem[1] = 0x003120b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTULess)
{
    write_reg(2, 0xfffffffe);
    write_reg(3, 0xffffffff);
    instr_mem[0] = 0;
    // sltu     x1,x2,x3
    instr_mem[1] = 0x003130b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTUNotLess)
{
    write_reg(2, 0xffffffff);
    write_reg(3, 0xfffffffe);
    instr_mem[0] = 0;
    // sltu     x1,x2,x3
    instr_mem[1] = 0x003130b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, XOR)
{
    write_reg(2, 0x7);
    write_reg(3, 0x9);
    instr_mem[0] = 0;
    // xor     x1,x2,x3
    instr_mem[1] = 0x003140b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xe, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRL)
{
    write_reg(2, 0x5);
    write_reg(3, 0x1);
    instr_mem[0] = 0;
    // srl     x1,x2,x3
    instr_mem[1] = 0x003150b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRA)
{
    write_reg(2, 0x80000000);
    write_reg(3, 15);
    instr_mem[0] = 0;
    // sra     x1,x2,x3
    instr_mem[1] = 0x403150b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xffff0000, instr.rd_val);
}

TEST_F(RXVCoreTestbench, OR)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    instr_mem[0] = 0;
    // or     x1,x2,x3
    instr_mem[1] = 0x003160b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xf, instr.rd_val);
}

TEST_F(RXVCoreTestbench, AND)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    instr_mem[0] = 0;
    // and     x1,x2,x3
    instr_mem[1] = 0x003170b3;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x1, instr.rd_val);
}

// Register-Immediate Arithmetic

TEST_F(RXVCoreTestbench, ADDI)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // addi     x1,x2,3
    instr_mem[1] = 0x00310093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(5, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLLI)
{
    write_reg(2, 2);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // slli     x1,x2,3
    instr_mem[1] = 0x00311093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2 << 3, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTILess)
{
    write_reg(2, -2);
    write_reg(3, -1);
    instr_mem[0] = 0;
    // slti     x1,x2,-1
    instr_mem[1] = 0xfff12093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTINotLess)
{
    write_reg(2, 4);
    write_reg(3, 3);
    instr_mem[0] = 0;
    // slti     x1,x2,3
    instr_mem[1] = 0x00312093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTIULess)
{
    write_reg(2, 0xfffffffe);
    write_reg(3, 0xffffffff);
    instr_mem[0] = 0;
    // sltiu     x1,x2,-1
    instr_mem[1] = 0xfff13093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTIUNotLess)
{
    write_reg(2, 0xffffffff);
    write_reg(3, 0xfffffffe);
    instr_mem[0] = 0;
    // sltiu     x1,x2,-2
    instr_mem[1] = 0xffe13093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, XORI)
{
    write_reg(2, 0x7);
    write_reg(3, 0x9);
    instr_mem[0] = 0;
    // xori     x1,x2,9
    instr_mem[1] = 0x00914093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xe, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRLI)
{
    write_reg(2, 0x5);
    write_reg(3, 0x1);
    instr_mem[0] = 0;
    // srli     x1,x2,1
    instr_mem[1] = 0x00115093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRAI)
{
    write_reg(2, 0x80000000);
    write_reg(3, 15);
    instr_mem[0] = 0;
    // srai     x1,x2,15
    instr_mem[1] = 0x40f15093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xffff0000, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ORI)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    instr_mem[0] = 0;
    // ori     x1,x2,7
    instr_mem[1] = 0x00716093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xf, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ANDI)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    instr_mem[0] = 0;
    // andi     x1,x2,x3
    instr_mem[1] = 0x00717093;
    cycle(10);

    auto instr = retired_instructions[0];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ExecForwarding)
{
    write_reg(1, 0);
    instr_mem[0] = 0;
    // addi    x1,x1,1
    instr_mem[1] = 0x00108093;
    instr_mem[2] = 0x00108093;
    instr_mem[3] = 0x00108093;
    cycle(20);

    auto instr = retired_instructions[2];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x3, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ExecForwarding2)
{
    write_reg(1, 0);
    instr_mem[0] = 0;
    // addi    x1,x1,1
    instr_mem[1] = 0x00108093;
    // addi    x2,x2,1
    instr_mem[2] = 0x00110113;
    // addi    x1,x1,1
    instr_mem[3] = 0x00108093;
    cycle(20);

    auto instr = retired_instructions[2];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x2, instr.rd_val);
}