#include <iostream>
#include <vector>
#include <map>
#include <cstring>

#include <gmock/gmock.h>

#include "VerilogTestbench.h"
#include "VRXVCore.h"

static const uint32_t NOP = 0x00000013;

// clang-format off
enum CSRID {
    MVENDORID   = 0x0F11,
    MARCHID     = 0x0F12,
    MIMPID      = 0x0F13,
    MHARTID     = 0x0F14,
    MSTATUS     = 0x0300,
    MISA        = 0x0301,
    MIE         = 0x0304,
    MTVEC       = 0x0305,
    MCOUNTEREN  = 0x0306,
    MSCRATCH    = 0x0340,
    MEPC        = 0x0341,
    MCAUSE      = 0x0342,
    MTVAL       = 0x0343,
    MIP         = 0x0344,
};


enum ExCause {
    EX_INSTR_ALIGN   = 0,
    EX_INSTR_ACCESS  = 1,
    EX_ILLEGAL_INSTR = 2,
    EX_BREAKPOINT    = 3,
    EX_LOAD_ALIGN    = 4,
    EX_LOAD_ACCESS   = 5,
    EX_STORE_ALIGN   = 6,
    EX_STORE_ACCESS  = 7,
    EX_ECALL_U       = 8,
    EX_ECALL_S       = 9,
    EX_ECALL_M       = 11,
    EX_INSTR_PF      = 12,
    EX_LOAD_PF       = 13,
    EX_STORE_PF      = 15
};
// clang-format on

struct CSRAccess {
    uint32_t wmask;
    uint32_t wdata;
    uint32_t rmask;
    uint32_t rdata;
};

bool operator==(const CSRAccess &lhs, const CSRAccess &rhs)
{
    return lhs.wmask == rhs.wmask && lhs.wdata == rhs.wdata &&
           lhs.rmask == rhs.rmask && lhs.rdata == rhs.rdata;
}

using CSRMap = std::map<uint16_t, CSRAccess>;

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
    static constexpr int num_instructions = 512 * 1024 * 4;

    RXVCoreTestbench()
    {
        reg_file_scope = svGetScopeFromName("TOP.RXVCore.RegFile");
        csr_scope = svGetScopeFromName("TOP.RXVCore");

        set_mtvec(0x8000);

        for (auto m = 0; m < num_instructions; ++m)
            mem[m] = NOP;

        periodic(ClockSetup, [&] {
            after_n_cycles(0, [&] {
                if ((this->dut.i_addr >> 2) >= num_instructions)
                    FAIL() << "out of bounds instruction access" << std::endl;
                this->dut.i_data = this->mem[this->dut.i_addr >> 2];
            });
        });

        periodic(ClockSetup, [&] {
            if (!this->dut.d_access)
                return;
            if (this->dut.d_addr & 0x3)
                throw std::runtime_error("error: unaligned data access");

            uint32_t mask = ((this->dut.d_bytesel & 1) ? 0x000000ff : 0) |
                            ((this->dut.d_bytesel & 2) ? 0x0000ff00 : 0) |
                            ((this->dut.d_bytesel & 4) ? 0x00ff0000 : 0) |
                            ((this->dut.d_bytesel & 8) ? 0xff000000 : 0);
            uint32_t addr = this->dut.d_addr;

            if ((addr >> 2) >= num_instructions)
                FAIL() << "out of bounds data access" << std::endl;

            if (this->dut.d_wren) {
                uint32_t wdata = this->dut.d_wdata;
                after_n_cycles(0, [&, addr, wdata, mask] {
                    this->mem[addr >> 2] &= ~mask;
                    this->mem[addr >> 2] |= wdata & mask;
                });
            } else {
                after_n_cycles(0, [&, addr, mask] {
                    this->dut.d_rdata = this->mem[addr >> 2] & mask;
                });
            }
        });
        periodic(ClockCapture, [&] {
            if (!this->dut.rvfi_valid)
                return;

            auto instr_idx = retired_instructions.size();
            RetiredInstruction ri{this->dut.rvfi_insn, this->dut.rvfi_pc_rdata,
                                  this->dut.rvfi_pc_wdata,
                                  this->dut.rvfi_rd_wdata,
                                  this->dut.rvfi_rd_addr};
            retired_instructions.push_back(ri);

#define CSR_ACCESS(id, name)                                      \
    ({                                                            \
        if (this->dut.rvfi_csr_##name##_rmask ||                  \
            this->dut.rvfi_csr_##name##_wmask)                    \
            retired_csrs[instr_idx][id] =                         \
                CSRAccess{this->dut.rvfi_csr_##name##_wmask,      \
                          this->dut.rvfi_csr_##name##_wmask       \
                              ? this->dut.rvfi_csr_##name##_wdata \
                              : 0,                                \
                          this->dut.rvfi_csr_##name##_rmask,      \
                          this->dut.rvfi_csr_##name##_rmask       \
                              ? this->dut.rvfi_csr_##name##_rdata \
                              : 0};                               \
    })
            CSR_ACCESS(MARCHID, marchid);
            CSR_ACCESS(MSCRATCH, mscratch);
            CSR_ACCESS(MCAUSE, mcause);
            CSR_ACCESS(MTVAL, mtval);
            CSR_ACCESS(MTVEC, mtvec);
            CSR_ACCESS(MEPC, mepc);
        });
    }

    void write_reg(int r, int v)
    {
        svSetScope(reg_file_scope);
        this->dut.write_reg(r, v);
    }

    void write_csr(enum CSRID csr, uint32_t v)
    {
        svSetScope(csr_scope);
        this->dut.write_csr(csr, v);
    }

    void set_mtvec(uint32_t addr)
    {
        mtvec_addr = addr;

        write_csr(MTVEC, addr);
    }

    void expect_exception(int instr_idx,
                          uint32_t pc,
                          uint32_t val,
                          ExCause cause)
    {
        csr_accesses[instr_idx][MCAUSE] = {0xffffffff, cause, 0, 0};
        csr_accesses[instr_idx][MEPC] = {0xffffffff, pc, 0, 0};
        csr_accesses[instr_idx][MTVAL] = {0xffffffff, val, 0, 0};
        csr_accesses[instr_idx][MTVEC] = {0x00000000, 0x00000000, 0xffffffff,
                                          mtvec_addr};
    }

    void check_exceptions()
    {
            EXPECT_THAT(retired_csrs,
                        ::testing::ContainerEq(csr_accesses));
    }

    std::vector<RetiredInstruction> retired_instructions;
    uint32_t mem[num_instructions];
    std::map<int, CSRMap> csr_accesses, retired_csrs;

private:
    svScope reg_file_scope;
    svScope csr_scope;
    uint32_t mtvec_addr;
};

TEST_F(RXVCoreTestbench, LUI)
{
    mem[1] = 0xdeadb537;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0xdeadb000, instr.rd_val);
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, AUIPC)
{
    // auipc x10, 0xeef
    mem[1] = 0x00eef517;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00eef004, instr.rd_val);
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, JAL)
{
    // jal x10, 0x100
    mem[1] = 0x1000056f;
    mem[2] = 0xdeadbeef;
    mem[0x104 / 4] = 0x0100056f;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00000008, instr.rd_val);
    EXPECT_EQ(0x104, instr.next_pc);

    instr = retired_instructions[2];
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
    // jalr    x10,256(x2)
    mem[1] = 0x10010567;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(10, instr.rd);
    EXPECT_EQ(0x00000008, instr.rd_val);
    EXPECT_EQ(256 + 0x200, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BEQTaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x200);
    // beq     x2,x3,c
    mem[1] = 0x00310463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BEQNotTaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x201);
    // beq     x2,x3,c
    mem[1] = 0x00310463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BNETaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x201);
    // bne     x2,x3,c
    mem[1] = 0x00311463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BNENotTaken)
{
    write_reg(2, 0x200);
    write_reg(3, 0x200);
    // bne     x2,x3,c
    mem[1] = 0x00311463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTTaken)
{
    write_reg(2, -2);
    write_reg(3, -1);
    // blt     x2,x3,c
    mem[1] = 0x00314463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTNotTaken)
{
    write_reg(2, 1);
    write_reg(3, -1);
    // blt     x2,x3,c
    mem[1] = 0x00314463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGETakenGreater)
{
    write_reg(2, 2);
    write_reg(3, 1);
    // bge     x2,x3,c
    mem[1] = 0x00315463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGETakenEqual)
{
    write_reg(2, 2);
    write_reg(3, 2);
    // bge     x2,x3,c
    mem[1] = 0x00315463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGENotTaken)
{
    write_reg(2, -2);
    write_reg(3, -1);
    // bge     x2,x3,c
    mem[1] = 0x00315463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTUTaken)
{
    write_reg(2, 2);
    write_reg(3, 3);
    // bltu     x2,x3,c
    mem[1] = 0x00316463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BLTUNotTaken)
{
    write_reg(2, -2);
    write_reg(3, 2);
    // bltu     x2,x3,c
    mem[1] = 0x00316463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGEUTakenGreater)
{
    write_reg(2, -1);
    write_reg(3, -2);
    // bgeu     x2,x3,c
    mem[1] = 0x00317463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

TEST_F(RXVCoreTestbench, BGEUTakenEqual)
{
    write_reg(2, 2);
    write_reg(3, 2);
    // bgeu     x2,x3,c
    mem[1] = 0x00317463;
    mem[2] = 0xdeadbeef;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0xc, instr.next_pc);
}

// Register-Register Arithmetic

TEST_F(RXVCoreTestbench, ADD)
{
    write_reg(2, 2);
    write_reg(3, 3);
    // add     x1,x2,x3
    mem[1] = 0x003100b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(5, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SUB)
{
    write_reg(2, 2);
    write_reg(3, 3);
    // sub     x1,x2,x3
    mem[1] = 0x403100b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xffffffff, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLL)
{
    write_reg(2, 2);
    write_reg(3, 3);
    // sll     x1,x2,x3
    mem[1] = 0x003110b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2 << 3, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTLess)
{
    write_reg(2, -2);
    write_reg(3, -1);
    // slt     x1,x2,x3
    mem[1] = 0x003120b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTNotLess)
{
    write_reg(2, 4);
    write_reg(3, 3);
    // slt     x1,x2,x3
    mem[1] = 0x003120b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTULess)
{
    write_reg(2, 0xfffffffe);
    write_reg(3, 0xffffffff);
    // sltu     x1,x2,x3
    mem[1] = 0x003130b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTUNotLess)
{
    write_reg(2, 0xffffffff);
    write_reg(3, 0xfffffffe);
    // sltu     x1,x2,x3
    mem[1] = 0x003130b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, XOR)
{
    write_reg(2, 0x7);
    write_reg(3, 0x9);
    // xor     x1,x2,x3
    mem[1] = 0x003140b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xe, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRL)
{
    write_reg(2, 0x5);
    write_reg(3, 0x1);
    // srl     x1,x2,x3
    mem[1] = 0x003150b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRA)
{
    write_reg(2, 0x80000000);
    write_reg(3, 15);
    // sra     x1,x2,x3
    mem[1] = 0x403150b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xffff0000, instr.rd_val);
}

TEST_F(RXVCoreTestbench, OR)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    // or     x1,x2,x3
    mem[1] = 0x003160b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xf, instr.rd_val);
}

TEST_F(RXVCoreTestbench, AND)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    // and     x1,x2,x3
    mem[1] = 0x003170b3;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x1, instr.rd_val);
}

// Register-Immediate Arithmetic

TEST_F(RXVCoreTestbench, ADDI)
{
    write_reg(2, 2);
    write_reg(3, 3);
    // addi     x1,x2,3
    mem[1] = 0x00310093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(5, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLLI)
{
    write_reg(2, 2);
    write_reg(3, 3);
    // slli     x1,x2,3
    mem[1] = 0x00311093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2 << 3, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTILess)
{
    write_reg(2, -2);
    write_reg(3, -1);
    // slti     x1,x2,-1
    mem[1] = 0xfff12093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTINotLess)
{
    write_reg(2, 4);
    write_reg(3, 3);
    // slti     x1,x2,3
    mem[1] = 0x00312093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTIULess)
{
    write_reg(2, 0xfffffffe);
    write_reg(3, 0xffffffff);
    // sltiu     x1,x2,-1
    mem[1] = 0xfff13093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SLTIUNotLess)
{
    write_reg(2, 0xffffffff);
    write_reg(3, 0xfffffffe);
    // sltiu     x1,x2,-2
    mem[1] = 0xffe13093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
}

TEST_F(RXVCoreTestbench, XORI)
{
    write_reg(2, 0x7);
    write_reg(3, 0x9);
    // xori     x1,x2,9
    mem[1] = 0x00914093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xe, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRLI)
{
    write_reg(2, 0x5);
    write_reg(3, 0x1);
    // srli     x1,x2,1
    mem[1] = 0x00115093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(2, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SRAI)
{
    write_reg(2, 0x80000000);
    write_reg(3, 15);
    // srai     x1,x2,15
    mem[1] = 0x40f15093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xffff0000, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ORI)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    // ori     x1,x2,7
    mem[1] = 0x00716093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0xf, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ANDI)
{
    write_reg(2, 0x9);
    write_reg(3, 0x7);
    // andi     x1,x2,x3
    mem[1] = 0x00717093;
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x1, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ExecForwarding)
{
    write_reg(1, 0);
    // addi    x1,x1,1
    mem[1] = 0x00108093;
    mem[2] = 0x00108093;
    mem[3] = 0x00108093;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x3, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ExecForwarding2)
{
    write_reg(1, 0);
    // addi    x1,x1,1
    mem[1] = 0x00108093;
    // addi    x2,x2,1
    mem[2] = 0x00110113;
    // addi    x1,x1,1
    mem[3] = 0x00108093;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(1, instr.rd);
    EXPECT_EQ(0x2, instr.rd_val);
}

TEST_F(RXVCoreTestbench, SW)
{
    write_reg(1, 0x100);
    write_reg(2, 0xa5a55a5a);
    // sw      x2,16(x1)
    mem[1] = 0x0020a823;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(0xa5a55a5aLU, mem[0x110 / sizeof(uint32_t)]);
}

TEST_F(RXVCoreTestbench, SH)
{
    write_reg(1, 0x100);
    write_reg(2, 0xa5a55a5a);
    // sh      x2,16(x1)
    mem[1] = 0x00209823;

    mem[0x110 / sizeof(uint32_t)] = 0xffff1234;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(0xffff5a5aLU, mem[0x110 / sizeof(uint32_t)]);
}

TEST_F(RXVCoreTestbench, SHUpper)
{
    write_reg(1, 0x102);
    write_reg(2, 0xffffa5a5);
    // sh      x2,16(x1)
    mem[1] = 0x00209823;

    mem[0x110 / sizeof(uint32_t)] = 0xffff1234;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(0xa5a51234, mem[0x110 / sizeof(uint32_t)]);
}

TEST_F(RXVCoreTestbench, SBAligned0)
{
    write_reg(1, 0x100);
    write_reg(2, 0xffffa5a5);
    // sb      x2,16(x1)
    mem[1] = 0x00208823;

    mem[0x110 / sizeof(uint32_t)] = 0xffff1234;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(0xffff12a5, mem[0x110 / sizeof(uint32_t)]);
}

TEST_F(RXVCoreTestbench, SBAligned1)
{
    write_reg(1, 0x101);
    write_reg(2, 0xffffa5a5);
    // sb      x2,16(x1)
    mem[1] = 0x00208823;

    mem[0x110 / sizeof(uint32_t)] = 0xffff1234;
    cycle(20);

    auto instr = retired_instructions[3];
    EXPECT_EQ(0x10, instr.next_pc);
    EXPECT_EQ(0xffffa534, mem[0x110 / sizeof(uint32_t)]);
}

TEST_F(RXVCoreTestbench, LW)
{
    write_reg(1, 0x100);
    write_reg(2, 0);
    // lw      x2,16(x1)
    mem[1] = 0x0100a103;

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x12345678, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LHUAligned)
{
    write_reg(1, 0x100);
    write_reg(2, 0);
    // lhu      x2,16(x1)
    mem[1] = 0x0100d103;

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x00005678, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LHUUnaligned)
{
    write_reg(1, 0x102);
    write_reg(2, 0);
    // lhu      x2,16(x1)
    mem[1] = 0x0100d103;

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x00001234, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LBU0)
{
    write_reg(1, 0x100);
    write_reg(2, 0);
    // lbu      x2,16(x1)
    mem[1] = 0x0100c103;

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x00000078, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LBU3)
{
    write_reg(1, 0x103);
    write_reg(2, 0);
    // lbu      x2,16(x1)
    mem[1] = 0x0100c103;

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x00000012, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LB)
{
    write_reg(1, 0x100);
    write_reg(2, 0);
    // lb      x2,16(x1)
    mem[1] = 0x01008103;

    mem[0x110 / sizeof(uint32_t)] = 0x00000081;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0xffffff81, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LH)
{
    write_reg(1, 0x100);
    write_reg(2, 0);
    // lh      x2,16(x1)
    mem[1] = 0x01009103;

    mem[0x110 / sizeof(uint32_t)] = 0x00008081;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8, instr.next_pc);
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0xffff8081, instr.rd_val);
}

TEST_F(RXVCoreTestbench, LWForward)
{
    write_reg(1, 0x100);
    write_reg(2, 0);
    // lw      x2,16(x1)
    mem[1] = 0x0100a103;
    // addi    x2,x2,0x678
    mem[2] = 0x67810113;

    mem[0x110 / sizeof(uint32_t)] = 0x12345000;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x12345000, instr.rd_val);

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x12345678, instr.rd_val);
}

TEST_F(RXVCoreTestbench, ReadMarchidCSRRW)
{
    write_reg(2, 0x12345678);
    write_reg(2, 0xdeadbeef);
    // csrrw   x2,marchid,x0
    mem[1] = 0xf1201173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x72787600, instr.rd_val);
    CSRMap expected;
    expected[MARCHID] = {0x00000000, 0x00000000, 0xffffffff, 0x72787600};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ReadWriteMscratchCSRRW)
{
    write_reg(1, 0x12345678);
    // csrrw   x2,mscratch,x1
    mem[1] = 0x34009173;
    // csrrw   x2,mscratch,x3
    mem[2] = 0x34019173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
    CSRMap expected;
    expected[MSCRATCH] = {0xffffffff, 0x12345678, 0xffffffff, 0};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x12345678, instr.rd_val);
    expected.clear();
    expected[MSCRATCH] = {0xffffffff, 0x00000000, 0xffffffff, 0x12345678};
    EXPECT_THAT(retired_csrs[2], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ReadWriteMscratchCSRRS)
{
    write_reg(1, 0x80018001);
    write_reg(3, 0x0000ffff);
    // csrrw   x2,mscratch,x1
    mem[1] = 0x34009173;
    // csrrs   x2,mscratch,x3
    mem[2] = 0x3401a173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
    CSRMap expected;
    expected[MSCRATCH] = {0xffffffff, 0x80018001, 0xffffffff, 0};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x80018001, instr.rd_val);
    expected.clear();
    expected[MSCRATCH] = {0xffffffff, 0x8001ffff, 0xffffffff, 0x80018001};
    EXPECT_THAT(retired_csrs[2], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ReadWriteMscratchCSRRC)
{
    write_reg(1, 0x80018001);
    write_reg(3, 0x0000ffff);
    // csrrw   x2,mscratch,x1
    mem[1] = 0x34009173;
    // csrrc   x2,mscratch,x3
    mem[2] = 0x3401b173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
    CSRMap expected;
    expected[MSCRATCH] = {0xffffffff, 0x80018001, 0xffffffff, 0};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x80018001, instr.rd_val);
    expected.clear();
    expected[MSCRATCH] = {0xffffffff, 0x80010000, 0xffffffff, 0x80018001};
    EXPECT_THAT(retired_csrs[2], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ReadWriteMscratchCSRRWI)
{
    // csrrwi   x2,mscratch,0x1c
    mem[1] = 0x340e5173;
    // csrrw   x2,mscratch,x3
    mem[2] = 0x34019173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
    CSRMap expected;
    expected[MSCRATCH] = {0xffffffff, 0x0000001c, 0xffffffff, 0};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x0000001c, instr.rd_val);
    expected.clear();
    expected[MSCRATCH] = {0xffffffff, 0x00000000, 0xffffffff, 0x0000001c};
    EXPECT_THAT(retired_csrs[2], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ReadWriteMscratchCSRRSI)
{
    write_reg(1, 0x80018001);
    // csrrw   x2,mscratch,x1
    mem[1] = 0x34009173;
    // csrrsi  x2,mscratch,0x1c
    mem[2] = 0x340e6173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
    CSRMap expected;
    expected[MSCRATCH] = {0xffffffff, 0x80018001, 0xffffffff, 0};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x80018001, instr.rd_val);
    expected.clear();
    expected[MSCRATCH] = {0xffffffff, 0x8001801d, 0xffffffff, 0x80018001};
    EXPECT_THAT(retired_csrs[2], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ReadWriteMscratchCSRRCI)
{
    write_reg(1, 0x800180ff);
    // csrrw   x2,mscratch,x1
    mem[1] = 0x34009173;
    // csrrci  x2,mscratch,0x1c
    mem[2] = 0x340e7173;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0, instr.rd_val);
    CSRMap expected;
    expected[MSCRATCH] = {0xffffffff, 0x800180ff, 0xffffffff, 0};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));

    instr = retired_instructions[2];
    EXPECT_EQ(2, instr.rd);
    EXPECT_EQ(0x800180ff, instr.rd_val);
    expected.clear();
    expected[MSCRATCH] = {0xffffffff, 0x800180e3, 0xffffffff, 0x800180ff};
    EXPECT_THAT(retired_csrs[2], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, LWUnaligned)
{
    write_reg(1, 0x101);
    write_reg(2, 0);

    // lw      x2,16(x1)
    mem[1] = 0x0100a103;
    // addi	x10,x10,1
    mem[2] = 0x00150513;
    expect_exception(1, 0x4, 0x111, EX_LOAD_ALIGN);

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8000, instr.next_pc);
    EXPECT_EQ(0, instr.rd);

    instr = retired_instructions[2];
    EXPECT_EQ(0, instr.rd);

    check_exceptions();
}

TEST_F(RXVCoreTestbench, SWUnaligned)
{
    write_reg(1, 0x101);
    write_reg(2, 0);

    // sw      x2,16(x1)
    mem[1] = 0x0020a823;
    // addi	x10,x10,1
    mem[2] = 0x00150513;
    expect_exception(1, 0x4, 0x111, EX_STORE_ALIGN);

    mem[0x110 / sizeof(uint32_t)] = 0x12345678;
    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8000, instr.next_pc);
    EXPECT_EQ(0, instr.rd);
    EXPECT_EQ(NOP, mem[0x100 / 4]);

    instr = retired_instructions[2];
    EXPECT_EQ(0, instr.rd);

    check_exceptions();
}

TEST_F(RXVCoreTestbench, IllegalInstr)
{
    // Illegal instruction
    mem[1] = 0xffffffff;
    // addi	x10,x10,1
    mem[2] = 0x00150513;
    expect_exception(1, 0x4, 0xffffffff, EX_ILLEGAL_INSTR);

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0x8000, instr.next_pc);
    EXPECT_EQ(0, instr.rd);

    instr = retired_instructions[2];
    EXPECT_EQ(0, instr.rd);

    check_exceptions();
}

TEST_F(RXVCoreTestbench, JALRMisalign)
{
    write_reg(2, 0x203);
    // jalr    x10,256(x2)
    mem[1] = 0x10010567;
    mem[2] = 0xdeadbeef;

    expect_exception(1, 0x4, 0x203 + 256, EX_INSTR_ALIGN);
    cycle(10);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0, instr.rd);
    EXPECT_EQ(0x8000, instr.next_pc);
}

TEST_F(RXVCoreTestbench, MRET)
{
    write_csr(MEPC, 0x1000);
    write_reg(1, 0x800180ff);
    // mret
    mem[1] = 0x30200073;

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0, instr.rd);
    EXPECT_EQ(0x1000, instr.next_pc);
    CSRMap expected;
    expected[MEPC] = {0, 0, 0xffffffff, 0x0001000};
    EXPECT_THAT(retired_csrs[1], ::testing::ContainerEq(expected));
}

TEST_F(RXVCoreTestbench, ECALL)
{
    write_reg(1, 0x800180ff);
    // ecall
    mem[1] = 0x00000073;
    expect_exception(1, 0x4, 0, EX_ECALL_M);

    cycle(20);

    auto instr = retired_instructions[1];
    EXPECT_EQ(0, instr.rd);
    EXPECT_EQ(0x8000, instr.next_pc);

    check_exceptions();
}