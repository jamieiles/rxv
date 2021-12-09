#include <iostream>
#include <iterator>
#include <sstream>
#include <vector>
#include <algorithm>

#include "VerilogTestbench.h"
#include "VRXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper__Syms.h"
#include "VRXVCoreEmulWrapper_RXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_BusTransactor.h"
#include "VRXVCoreEmulWrapper_RXVCore.h"
#include "MemoryDevice.h"
#include "MockMemoryBus.h"
#include "SimTracer.h"

struct InstructionRecord {
    uint32_t pc;
    std::pair<int, uint32_t> reg_write;
    std::vector<std::pair<int, uint32_t>> csr_writes;
    bool excepted;
};

class TestbenchTracer : public SimTracer
{
public:
    TestbenchTracer(const std::optional<std::string> filename)
        : SimTracer(filename), num_instructions(0), last_pc(0x80000000)
    {
        for (auto i = 0; i < 32; ++i)
            shadow_regs[i] = 0;
        for (auto i = 0; i < (1 << 12); ++i)
            shadow_csrs[i] = 0;
    }

    virtual void trace_write_reg(int id, int r, uint32_t v) override
    {
        SimTracer::trace_write_reg(id, r, v);
        instruction_map[id].reg_write = std::make_pair(r, v);
    }

    virtual void trace_write_csr(int id, int r, uint32_t v) override
    {
        instruction_map[id].csr_writes.emplace_back(std::make_pair(r, v));

        SimTracer::trace_write_csr(id, r, v);
    }

    virtual void trace_read_reg(int id, int r, uint32_t v) override
    {
        SimTracer::trace_read_reg(id, r, v);
    }

    virtual void trace_start_instruction(int id,
                                         uint32_t pc,
                                         uint32_t instr,
                                         uint64_t cycle,
                                         PrivilegeLevel level) override
    {
        SimTracer::trace_start_instruction(id, pc, instr, cycle, level);
        instruction_map[id] = InstructionRecord();
        instruction_map[id].pc = pc;
    }

    virtual void trace_exception(int id) override
    {
        instruction_map[id].excepted = true;
        SimTracer::trace_exception(id);
    }

    virtual void trace_end_instruction(int id) override
    {
        SimTracer::trace_end_instruction(id);

        auto &instr = instruction_map[id];
        if (instr.reg_write.first)
            shadow_regs[instr.reg_write.first] = instr.reg_write.second;
        for (auto &csr : instr.csr_writes)
            shadow_csrs[csr.first] = csr.second;
        last_pc = instr.pc;

        ++num_instructions;
    }

    uint32_t read_reg(int id) const
    {
        if (id < 0 || id >= 32)
            throw std::runtime_error("invalid GPR");

        return shadow_regs[id];
    }

    uint32_t read_csr(RXV::Trace::CSRId id) const
    {
        return shadow_csrs[id];
    }

    int get_num_instructions() const
    {
        return num_instructions;
    }

    uint32_t get_last_pc() const
    {
        return last_pc;
    }

private:
    uint32_t shadow_regs[32];
    uint32_t shadow_csrs[4096];
    int num_instructions;
    uint32_t last_pc;
    std::map<int, InstructionRecord> instruction_map;
};

class RXVCoreEmulWrapperTest
    : public VerilogTestbench<VRXVCoreEmulWrapper>
    , public ::testing::Test
{
public:
    RXVCoreEmulWrapperTest()
    {
        tracer =
            std::make_shared<TestbenchTracer>(current_test_name() + ".trace");
        this->dut.RXVCoreEmulWrapper->RXVCore->tracer = tracer;
        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024);
        this->dut.RXVCoreEmulWrapper->IBusTransactor->set_bus(bus);
        this->dut.RXVCoreEmulWrapper->DBusTransactor->set_bus(bus);
    }

    void load(const std::string &objdump)
    {
        std::istringstream line_stream(objdump);
        std::string line;

        while (std::getline(line_stream, line)) {
            std::istringstream ss(line);
            std::vector<std::string> tokens;

            std::copy(std::istream_iterator<std::string>(ss),
                      std::istream_iterator<std::string>(),
                      std::back_inserter(tokens));

            if (tokens.size() == 0)
                continue;

            auto addr = strtoul(tokens[0].c_str(), NULL, 16);
            auto instr = strtoul(tokens[1].c_str(), NULL, 16);

            bus->write(0x80000000 + addr, instr, 0xf);
        }
    }

    std::shared_ptr<MemoryBus> bus;
    std::shared_ptr<TestbenchTracer> tracer;
};

TEST_F(RXVCoreEmulWrapperTest, InstructionFetches)
{
    load(R"objdump(
         0:   00000093                li      x1,0
         4:   00a00113                li      x2,10
         8:   00108093                addi    x1,x1,1
         c:   fe20cee3                blt     x1,x2,0x8
        10:   0f000513                li      x10,240
        14:   000005ef                jal     x11,0x14
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000014; ++i)
        cycle();

    EXPECT_EQ(tracer->read_reg(1), 10);
    EXPECT_EQ(tracer->read_reg(2), 10);
    EXPECT_EQ(tracer->read_reg(10), 240);
    EXPECT_EQ(tracer->read_reg(11), 0x80000018);
}

TEST_F(RXVCoreEmulWrapperTest, ALUBypass)
{
    load(R"objdump(
         0:   00108093                addi    x1,x1,1
         4:   00108093                addi    x1,x1,1
         8:   00108093                addi    x1,x1,1
         c:   00108093                addi    x1,x1,1
        10:   00108093                addi    x1,x1,1
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000010; ++i)
        cycle();

    EXPECT_EQ(tracer->read_reg(1), 5);
}

TEST_F(RXVCoreEmulWrapperTest, NoBypassX0)
{
    load(R"objdump(
         0:   00100013                add     x0,x0,1
         4:   00100013                add     x0,x0,1
         8:   00100013                add     x0,x0,1
         c:   00100013                add     x0,x0,1
        10:   000080b3                add     x1,x1,x0
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000010; ++i)
        cycle();

    EXPECT_EQ(tracer->read_reg(1), 0);
}

TEST_F(RXVCoreEmulWrapperTest, JALR)
{
    load(R"objdump(
         0:   00100093                li      x1,1
         4:   00c000ef                jal     x1,0x10
         8:   0dc00193                li      x3,220
         c:   0000006f                j       0xc
        10:   0ac00113                li      x2,172
        14:   00008067                ret
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x8000000c; ++i)
        cycle();

    EXPECT_EQ(tracer->read_reg(1), 0x80000008);
    EXPECT_EQ(tracer->read_reg(3), 220);
    EXPECT_EQ(tracer->read_reg(2), 172);
}

TEST_F(RXVCoreEmulWrapperTest, BackToBackJumps)
{
    load(R"objdump(
         0:   0040006f                j       0x4
         4:   0040006f                j       0x8
         8:   0040006f                j       0xc
         c:   00150513                addi    x10,x10,1
        10:   ff1ff06f                j       0x0
    )objdump");

    while (tracer->get_num_instructions() != 5)
        cycle();

    EXPECT_EQ(tracer->read_reg(10), 1);
}

TEST_F(RXVCoreEmulWrapperTest, LUI)
{
    load(R"objdump(
         0:   800010b7                lui     x1,0x80001
         4:   fffff137                lui     x2,0xfffff
    )objdump");

    while (tracer->get_num_instructions() != 2)
        cycle();

    EXPECT_EQ(tracer->read_reg(1), 0x80001 << 12);
    EXPECT_EQ(tracer->read_reg(2), 0xfffff << 12);
}

TEST_F(RXVCoreEmulWrapperTest, AUIPC)
{
    load(R"objdump(
         0:   00000013                nop
         4:   00008097                auipc   x1,0x8
         8:   00000013                nop
    )objdump");

    while (tracer->get_num_instructions() != 3)
        cycle();

    EXPECT_EQ(tracer->read_reg(1), 0x80000004 + (8 << 12));
}

TEST_F(RXVCoreEmulWrapperTest, CSRRW)
{
    load(R"objdump(
         0:   deadc0b7                lui     x1,0xdeadc
         4:   eef08093                addi    x1,x1,-273 # 0xdeadbeef
         8:   34009173                csrrw   x2,mscratch,x1
         c:   aa55a137                lui     x2,0xaa55a
        10:   5a510113                addi    x2,x2,1445 # 0xaa55a5a5
        14:   340111f3                csrrw   x3,mscratch,x2
        18:   34002273                csrr    x4,mscratch
        1c:   00000013                nop
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x8000001c; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(2), 0xaa55a5a5);
    EXPECT_EQ(tracer->read_reg(3), 0xdeadbeef);
    EXPECT_EQ(tracer->read_reg(4), 0xaa55a5a5);
}

TEST_F(RXVCoreEmulWrapperTest, CSRRS)
{
    load(R"objdump(
          0:   000010b7                lui     x1,0x1
          4:   f0108093                addi    x1,x1,-255 # 0xf01
          8:   11111137                lui     x2,0x11111
          c:   11110113                addi    x2,x2,273 # 0x11111111
         10:   34011073                csrw    mscratch,x2
         14:   3400b1f3                csrrc   x3,mscratch,x1
         18:   34002273                csrr    x4,mscratch
         1c:   00000013                nop
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x8000001c; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(1), 0x00000f01);
    EXPECT_EQ(tracer->read_reg(2), 0x11111111);
    EXPECT_EQ(tracer->read_reg(3), 0x11111111);
    EXPECT_EQ(tracer->read_reg(4), 0x11111010);
}

TEST_F(RXVCoreEmulWrapperTest, CSRZeroNoWrite)
{
    load(R"objdump(
          0:   111110b7                lui     x1,0x11111
          4:   11108093                addi    x1,x1,273 # 0x11111111
          8:   34009073                csrw    mscratch,x1
          c:   34003073                csrc    mscratch,x0
         10:   34002173                csrr    x2,mscratch
         14:   34007073                csrci   mscratch,0
         18:   340021f3                csrr    x3,mscratch
         1c:   00000013                nop
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x8000001c; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(1), 0x11111111);
    EXPECT_EQ(tracer->read_reg(2), 0x11111111);
    EXPECT_EQ(tracer->read_reg(3), 0x11111111);
}

TEST_F(RXVCoreEmulWrapperTest, ReadVendorId)
{
    load(R"objdump(
          0:   f11020f3                csrr    x1,mvendorid
          4:   00000013                nop
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000004; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(1), 0x53454c49);
}

TEST_F(RXVCoreEmulWrapperTest, MRET)
{
    load(R"objdump(
          0:   00000097                auipc   x1,0x0
          4:   02408093                addi    x1,x1,36 # 0x24
          8:   34109073                csrw    mepc,x1
          c:   00000013                nop
         10:   30200073                mret
         14:   00f00093                li      x1,15
         18:   0000006f                j       0x18
         1c:   00000013                nop
         20:   00000013                nop
         24:   00100093                li      x1,1
         28:   ffdff06f                j       0x24
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000024; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(1), 1);
}

TEST_F(RXVCoreEmulWrapperTest, IllegalInstruction)
{
    load(R"objdump(
          0:   00000013                nop
          4:   00200073                uret
    )objdump");

    for (int i = 0; i < 512 && tracer->get_num_instructions() != 2; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000004);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0x00200073);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x00000002);

    cycle(128);
}

TEST_F(RXVCoreEmulWrapperTest, MTVECAlignVectored)
{
    load(R"objdump(
          0:   fff00093                li      x1,-1
          4:   30509073                csrw    mtvec,x1
          8:   30502173                csrr    x2,mtvec
    )objdump");

    for (int i = 0; i < 512 && tracer->get_num_instructions() != 3; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0xffffffc1);
    EXPECT_EQ(tracer->read_reg(2), 0xffffffc1);
}

TEST_F(RXVCoreEmulWrapperTest, MTVECAlignDirect)
{
    load(R"objdump(
          0:   ffe00093                li      x1,-2
          4:   30509073                csrw    mtvec,x1
          8:   30502173                csrr    x2,mtvec
    )objdump");

    for (int i = 0; i < 512 && tracer->get_num_instructions() != 3; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0xfffffffc);
    EXPECT_EQ(tracer->read_reg(2), 0xfffffffc);
}

TEST_F(RXVCoreEmulWrapperTest, ExceptionHandling)
{
    load(R"objdump(
            0:   00000097                auipc   x1,0x0
            4:   01c08093                addi    x1,x1,28 # 0x1c
            8:   30509073                csrw    mtvec,x1
            c:   00200113                li      x2,2
           10:   00200073                uret
           14:   00300193                li      x3,3
           18:   0000006f                j       0x18
           1c:   00a00513                li      x10,10
           20:   341025f3                csrr    x11,mepc
           24:   00458593                addi    x11,x11,4
           28:   34159073                csrw    mepc,x11
           2c:   001a0a13                addi    x20,x20,1
           30:   30200073                mret
    )objdump");

    for (int i = 0; i < 512; ++i) {
        cycle();
        if (i == 511 && tracer->get_last_pc() != 0x80000018)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0x8000001c);
    EXPECT_EQ(tracer->read_reg(2), 2);
    EXPECT_EQ(tracer->read_reg(3), 3);
    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_reg(11), 0x80000014);
    EXPECT_EQ(tracer->read_reg(20), 1);
}

TEST_F(RXVCoreEmulWrapperTest, RepeatedExceptionHandling)
{
    load(R"objdump(
         0:   00000097                auipc   x1,0x0
         4:   02008093                addi    x1,x1,32 # 0x20
         8:   30509073                csrw    mtvec,x1
         c:   00200113                li      x2,2
        10:   00200073                uret
        14:   00200073                uret
        18:   00300193                li      x3,3
        1c:   0000006f                j       0x1c
        20:   00a00513                li      x10,10
        24:   341025f3                csrr    x11,mepc
        28:   00458593                addi    x11,x11,4
        2c:   34159073                csrw    mepc,x11
        30:   001a0a13                addi    x20,x20,1
        34:   30200073                mret
    )objdump");

    for (int i = 0; i < 512; ++i) {
        cycle();
        if (i == 511 && tracer->get_last_pc() != 0x8000001c)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0x80000020);
    EXPECT_EQ(tracer->read_reg(2), 2);
    EXPECT_EQ(tracer->read_reg(3), 3);
    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_reg(11), 0x80000018);
    EXPECT_EQ(tracer->read_reg(20), 2);
}

TEST_F(RXVCoreEmulWrapperTest, KilledIllegal)
{
    load(R"objdump(
         0:   0000006f                j       0x0
         4:   00200073                uret
    )objdump");

    for (int i = 0; i < 512; ++i)
        cycle();

    EXPECT_GT(tracer->get_num_instructions(), 16);
    EXPECT_EQ(tracer->get_last_pc(), 0x80000000);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0);
}

TEST_F(RXVCoreEmulWrapperTest, JALRMisalign)
{
    load(R"objdump(
         0:   00000097                auipc   x1,0x0
         4:   03008093                addi    x1,x1,48 # 0x30
         8:   30509073                csrw    mtvec,x1
         c:   00000097                auipc   x1,0x0
        10:   01c08093                addi    x1,x1,28 # 0x28
        14:   00308093                addi    x1,x1,3
        18:   000080e7                jalr    x1
        1c:   00100113                li      x2,1
        20:   0000006f                j       0x20
        24:   00300193                li      x3,3
        28:   00400213                li      x4,4
        2c:   0000006f                j       0x2c
        30:   00a00513                li      x10,10
        34:   341025f3                csrr    x11,mepc
        38:   00458593                addi    x11,x11,4
        3c:   34159073                csrw    mepc,x11
        40:   001a0a13                addi    x20,x20,1
        44:   30200073                mret
    )objdump");

    for (int i = 0; i < 512; ++i) {
        cycle();
        if (i == 511 && tracer->get_last_pc() != 0x80000020)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0x80000030);
    EXPECT_EQ(tracer->read_reg(2), 1);
    EXPECT_EQ(tracer->read_reg(4), 0);
    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_reg(20), 1);
}

TEST_F(RXVCoreEmulWrapperTest, FENCE)
{
    load(R"objdump(
         0:   0ff0000f                fence
         4:   0a50000f                fence   ir,ow
         8:   00100093                li      x1,1
    )objdump");

    for (int i = 0; i < 512 && tracer->get_num_instructions() != 3; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(1), 1);
}

TEST_F(RXVCoreEmulWrapperTest, WFI)
{
    load(R"objdump(
         0:   10500073                wfi
         4:   10500073                wfi
         8:   00100093                li      x1,1
    )objdump");

    for (int i = 0; i < 512 && tracer->get_num_instructions() != 3; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(1), 1);
}

TEST_F(RXVCoreEmulWrapperTest, ECALL)
{
    load(R"objdump(
          0:   00000097                auipc   x1,0x0
          4:   01408093                addi    x1,x1,20 # 0x14
          8:   30509073                csrw    mtvec,x1
          c:   00000073                ecall
         10:   0000006f                j       0x10
         14:   00a00513                li      x10,10
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000014; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x0000000b);
}

TEST_F(RXVCoreEmulWrapperTest, EBREAK)
{
    load(R"objdump(
          0:   00000097                auipc   x1,0x0
          4:   01408093                addi    x1,x1,20 # 0x14
          8:   30509073                csrw    mtvec,x1
          c:   00100073                ebreak
         10:   0000006f                j       0x10
         14:   00a00513                li      x10,10
    )objdump");

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000014; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x00000003);
}