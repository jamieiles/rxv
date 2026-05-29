// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <iostream>
#include <iterator>
#include <sstream>
#include <vector>
#include <algorithm>
#include <mutex>
#include "VerilogTestbench.h"
#include "VRXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper__Dpi.h"
#include "VRXVCoreEmulWrapper__Syms.h"
#include "VRXVCoreEmulWrapper_RXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_BusTransactor__Iz1.h"
#include "MemoryDevice.h"
#include "MockMemoryBus.h"
#include "SimTracer.h"
#include "RXVSim.h"
#include "SVUtils.h"

static const uint32_t PGD_BASE = 0x82000000;

enum mcause_type {
    M_SWINT = mcause_interrupt | 3,
    M_TINT = mcause_interrupt | 7,
    M_EINT = mcause_interrupt | 11,
    INSTR_ALIGN = 0,
    INSTR_ACCESS_FAULT = 1,
    ILLEGAL_INSTRUCTION = 2,
    BREAKPOINT = 3,
    LOAD_MISALIGN = 4,
    LOAD_ACCESS_FAULT = 5,
    STORE_MISALIGN = 6,
    STORE_ACCESS_FAULT = 7,
    U_ECALL = 8,
    S_ECALL = 9,
    M_ECALL = 11,
    INSTRUCTION_PAGE_FAULT = 12,
    LOAD_PAGE_FAULT = 13,
    STORE_PAGE_FAULT = 15,
};

static inline uint32_t vpn0(uint32_t va)
{
    return (va >> 12) & 0x3ff;
}

static inline uint32_t vpn1(uint32_t va)
{
    return (va >> 22) & 0x3ff;
}

struct InstructionRecord {
    uint32_t pc;
    std::pair<int, uint32_t> reg_write;
    std::vector<std::pair<int, uint32_t>> csr_writes;
    bool excepted;
};

class NCPeripheral : public IOPeripheral
{
public:
    NCPeripheral(uint32_t base, size_t len) : IOPeripheral(base, len)
    {
        memset(regs, 0, sizeof(regs));
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        if (offset + len > sizeof(regs) || len != 4)
            return;

        memcpy(&regs[offset / 4], v, sizeof(uint32_t));
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        if (offset + len > sizeof(regs) || len != 4)
            return;

        memcpy(v, &regs[offset / 4], sizeof(uint32_t));
    }

private:
    uint32_t regs[1024];
};

class TestbenchTracer : public SimTracer
{
public:
    TestbenchTracer(const std::optional<std::string> filename)
        : SimTracer(filename, std::nullopt), num_instructions(0), last_pc(0x80000000)
    {
        for (auto i = 0; i < 32; ++i)
            shadow_regs[i] = 0;
        for (auto i = 0; i < (1 << 12); ++i)
            shadow_csrs[i] = 0;
    }

    virtual void trace_write_reg(int id, int r, uint32_t v) override
    {
        const std::lock_guard<std::mutex> guard(lock);

        SimTracer::trace_write_reg(id, r, v);
        instruction_map[id].reg_write = std::make_pair(r, v);
    }

    virtual void trace_write_csr(int id, int r, uint32_t v) override
    {
        const std::lock_guard<std::mutex> guard(lock);

        instruction_map[id].csr_writes.emplace_back(std::make_pair(r, v));

        SimTracer::trace_write_csr(id, r, v);
    }

    virtual void trace_read_reg(int id, int r, uint32_t v) override
    {
        const std::lock_guard<std::mutex> guard(lock);

        SimTracer::trace_read_reg(id, r, v);
    }

    virtual void trace_start_instruction(int id,
                                         uint32_t pc,
                                         uint32_t pc_phys,
                                         uint32_t instr,
                                         uint64_t cycle,
                                         PrivilegeLevel level) override
    {
        const std::lock_guard<std::mutex> guard(lock);

        SimTracer::trace_start_instruction(id, pc, pc_phys, instr, cycle,
                                           level);
        instruction_map[id] = InstructionRecord();
        instruction_map[id].pc = pc;
    }

    virtual void trace_exception(int id) override
    {
        const std::lock_guard<std::mutex> guard(lock);

        instruction_map[id].excepted = true;
        SimTracer::trace_exception(id);
    }

    virtual void trace_end_instruction(int id) override
    {
        const std::lock_guard<std::mutex> guard(lock);

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
    std::mutex lock;
};

class RXVCoreEmulWrapperTest
    : public VerilogTestbench<VRXVCoreEmulWrapper>
    , public ::testing::Test
{
public:
    RXVCoreEmulWrapperTest() : next_free_page(PGD_BASE)
    {
        tracer =
            std::make_shared<TestbenchTracer>(current_test_name() + ".trace");
        sv_set_scope_name("TOP.RXVTrace");
        this->dut.dpi_set_trace_handle(tracer.get());

        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024 * 1024);

        sv_set_scope_name("TOP.RXVCoreEmulWrapper.IBusTransactor");
        this->dut.dpi_set_bus(bus.get());

        sv_set_scope_name("TOP.RXVCoreEmulWrapper.DBusTransactor");
        this->dut.dpi_set_bus(bus.get());

        pgd_base = alloc_page();
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

            bus->write(addr, instr, 0xf);
        }
    }

    void run_until(uint32_t pc, int timeout = 4096)
    {
        for (int i = 0; i < timeout && tracer->get_last_pc() != pc; ++i) {
            cycle();
            if (i == timeout - 1)
                FAIL() << "failed to complete test";
        }
    }

    void execute_n_instructions(int n, int timeout = 512)
    {
        int i = 0;

        while (tracer->get_num_instructions() != n) {
            cycle();
            ++i;

            if (i == timeout)
                FAIL() << "failed to complete test";
        }
    }

    uint32_t alloc_page()
    {
        auto r = next_free_page;

        next_free_page += 4096;

        return r;
    }

    void set_megapage_at(uint32_t va, uint32_t pa, uint32_t perms)
    {
        auto pte_addr = pgd_base + vpn1(va) * sizeof(uint32_t);

        bus->write(pte_addr, (pa >> 2) | perms | pte_valid, 0xf);
    }

    void set_page_at(uint32_t va, uint32_t pa, uint32_t perms)
    {
        auto pgd_addr = pgd_base + vpn1(va) * sizeof(uint32_t);
        auto pgd = bus->read(pgd_addr);

        if (!(pgd & pte_valid)) {
            auto p = alloc_page();

            bus->write(pgd_addr, (p >> 2) | pte_valid, 0xf);
        }

        auto pte_addr =
            ((bus->read(pgd_addr) & ~0x1) << 2) + vpn0(va) * sizeof(uint32_t);
        bus->write(pte_addr, (pa >> 2) | perms | pte_valid, 0xf);
    }

    std::shared_ptr<MemoryBus> bus;
    std::shared_ptr<TestbenchTracer> tracer;
    uint32_t next_free_page;
    uint32_t pgd_base;
};

TEST_F(RXVCoreEmulWrapperTest, InstructionFetches)
{
    load(R"objdump(
        80000000:   00000093                li      x1,0
        80000004:   00a00113                li      x2,10
        80000008:   00108093                addi    x1,x1,1
        8000000c:   fe20cee3                blt     x1,x2,0x8
        80000010:   0f000513                li      x10,240
        80000014:   000005ef                jal     x11,0x14
    )objdump");

    run_until(0x80000014);

    EXPECT_EQ(tracer->read_reg(1), 10);
    EXPECT_EQ(tracer->read_reg(2), 10);
    EXPECT_EQ(tracer->read_reg(10), 240);
    EXPECT_EQ(tracer->read_reg(11), 0x80000018);
}

TEST_F(RXVCoreEmulWrapperTest, ALUBypass)
{
    load(R"objdump(
        80000000:   00108093                addi    x1,x1,1
        80000004:   00108093                addi    x1,x1,1
        80000008:   00108093                addi    x1,x1,1
        8000000c:   00108093                addi    x1,x1,1
        80000010:   00108093                addi    x1,x1,1
    )objdump");

    run_until(0x80000010);

    EXPECT_EQ(tracer->read_reg(1), 5);
}

TEST_F(RXVCoreEmulWrapperTest, NoBypassX0)
{
    load(R"objdump(
        80000000:   00100013                add     x0,x0,1
        80000004:   00100013                add     x0,x0,1
        80000008:   00100013                add     x0,x0,1
        8000000c:   00100013                add     x0,x0,1
        80000010:   000080b3                add     x1,x1,x0
    )objdump");

    run_until(0x80000010);

    EXPECT_EQ(tracer->read_reg(1), 0);
}

TEST_F(RXVCoreEmulWrapperTest, JALR)
{
    load(R"objdump(
        80000000:   00100093                li      x1,1
        80000004:   00c000ef                jal     x1,0x10
        80000008:   0dc00193                li      x3,220
        8000000c:   0000006f                j       0xc
        80000010:   0ac00113                li      x2,172
        80000014:   00008067                ret
    )objdump");

    run_until(0x8000000c);

    EXPECT_EQ(tracer->read_reg(1), 0x80000008);
    EXPECT_EQ(tracer->read_reg(3), 220);
    EXPECT_EQ(tracer->read_reg(2), 172);
}

TEST_F(RXVCoreEmulWrapperTest, BackToBackJumps)
{
    load(R"objdump(
        80000000:   0040006f                j       0x4
        80000004:   0040006f                j       0x8
        80000008:   0040006f                j       0xc
        8000000c:   00150513                addi    x10,x10,1
        80000010:   ff1ff06f                j       0x0
    )objdump");

    execute_n_instructions(5);

    EXPECT_EQ(tracer->read_reg(10), 1);
}

TEST_F(RXVCoreEmulWrapperTest, LUI)
{
    load(R"objdump(
        80000000:   800010b7                lui     x1,0x80001
        80000004:   fffff137                lui     x2,0xfffff
    )objdump");

    execute_n_instructions(2);

    EXPECT_EQ(tracer->read_reg(1), 0x80001 << 12);
    EXPECT_EQ(tracer->read_reg(2), 0xfffff << 12);
}

TEST_F(RXVCoreEmulWrapperTest, AUIPC)
{
    load(R"objdump(
         80000000:   00000013                nop
         80000004:   00008097                auipc   x1,0x8
         80000008:   00000013                nop
    )objdump");

    execute_n_instructions(3);

    EXPECT_EQ(tracer->read_reg(1), 0x80000004 + (8 << 12));
}

TEST_F(RXVCoreEmulWrapperTest, CSRRW)
{
    load(R"objdump(
        80000000:   deadc0b7                lui     x1,0xdeadc
        80000004:   eef08093                addi    x1,x1,-273 # 0xdeadbeef
        80000008:   34009173                csrrw   x2,mscratch,x1
        8000000c:   aa55a137                lui     x2,0xaa55a
        80000010:   5a510113                addi    x2,x2,1445 # 0xaa55a5a5
        80000014:   340111f3                csrrw   x3,mscratch,x2
        80000018:   34002273                csrr    x4,mscratch
        8000001c:   00000013                nop
    )objdump");

    run_until(0x8000001c);

    EXPECT_EQ(tracer->read_reg(2), 0xaa55a5a5);
    EXPECT_EQ(tracer->read_reg(3), 0xdeadbeef);
    EXPECT_EQ(tracer->read_reg(4), 0xaa55a5a5);
}

TEST_F(RXVCoreEmulWrapperTest, CSRRS)
{
    load(R"objdump(
        80000000:   000010b7                lui     x1,0x1
        80000004:   f0108093                addi    x1,x1,-255 # 0xf01
        80000008:   11111137                lui     x2,0x11111
        8000000c:   11110113                addi    x2,x2,273 # 0x11111111
        80000010:   34011073                csrw    mscratch,x2
        80000014:   3400b1f3                csrrc   x3,mscratch,x1
        80000018:   34002273                csrr    x4,mscratch
        8000001c:   00000013                nop
    )objdump");

    run_until(0x8000001c);

    EXPECT_EQ(tracer->read_reg(1), 0x00000f01);
    EXPECT_EQ(tracer->read_reg(2), 0x11111111);
    EXPECT_EQ(tracer->read_reg(3), 0x11111111);
    EXPECT_EQ(tracer->read_reg(4), 0x11111010);
}

TEST_F(RXVCoreEmulWrapperTest, CSRZeroNoWrite)
{
    load(R"objdump(
        80000000:   111110b7                lui     x1,0x11111
        80000004:   11108093                addi    x1,x1,273 # 0x11111111
        80000008:   34009073                csrw    mscratch,x1
        8000000c:   34003073                csrc    mscratch,x0
        80000010:   34002173                csrr    x2,mscratch
        80000014:   34007073                csrci   mscratch,0
        80000018:   340021f3                csrr    x3,mscratch
        8000001c:   00000013                nop
    )objdump");

    run_until(0x8000001c);

    EXPECT_EQ(tracer->read_reg(1), 0x11111111);
    EXPECT_EQ(tracer->read_reg(2), 0x11111111);
    EXPECT_EQ(tracer->read_reg(3), 0x11111111);
}

TEST_F(RXVCoreEmulWrapperTest, ReadVendorId)
{
    load(R"objdump(
        80000000:   f11020f3                csrr    x1,mvendorid
        80000004:   00000013                nop
    )objdump");

    run_until(0x80000004);

    EXPECT_EQ(tracer->read_reg(1), 0x53454c49);
}

TEST_F(RXVCoreEmulWrapperTest, MRET)
{
    load(R"objdump(
        80000000:   00000097                auipc   x1,0x0
        80000004:   02408093                addi    x1,x1,36 # 0x24
        80000008:   34109073                csrw    mepc,x1
        8000000c:   00000013                nop
        80000010:   30200073                mret
        80000014:   00f00093                li      x1,15
        80000018:   0000006f                j       0x18
        8000001c:   00000013                nop
        80000020:   00000013                nop
        80000024:   00100093                li      x1,1
        80000028:   ffdff06f                j       0x24
    )objdump");

    run_until(0x80000024);

    EXPECT_EQ(tracer->read_reg(1), 1);
}

TEST_F(RXVCoreEmulWrapperTest, IllegalInstruction)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01008093                addi    x1,x1,16 # 0x80000010
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       00200073                uret
        80000010:       0000006f                j       0x80000010
    )objdump");

    execute_n_instructions(5);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x8000000c);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0x00200073);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x00000002);

    cycle(128);
}

TEST_F(RXVCoreEmulWrapperTest, MTVECAlignVectored)
{
    load(R"objdump(
        80000000:   fff00093                li      x1,-1
        80000004:   30509073                csrw    mtvec,x1
        80000008:   30502173                csrr    x2,mtvec
    )objdump");

    execute_n_instructions(3);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0xffffffc1);
    EXPECT_EQ(tracer->read_reg(2), 0xffffffc1);
}

TEST_F(RXVCoreEmulWrapperTest, MTVECAlignDirect)
{
    load(R"objdump(
        80000000:   ffe00093                li      x1,-2
        80000004:   30509073                csrw    mtvec,x1
        80000008:   30502173                csrr    x2,mtvec
    )objdump");

    execute_n_instructions(3);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0xfffffffc);
    EXPECT_EQ(tracer->read_reg(2), 0xfffffffc);
}

TEST_F(RXVCoreEmulWrapperTest, ExceptionHandling)
{
    load(R"objdump(
        80000000:   00000097                auipc   x1,0x0
        80000004:   01c08093                addi    x1,x1,28 # 0x1c
        80000008:   30509073                csrw    mtvec,x1
        8000000c:   00200113                li      x2,2
        80000010:   00200073                uret
        80000014:   00300193                li      x3,3
        80000018:   0000006f                j       0x18
        8000001c:   00a00513                li      x10,10
        80000020:   341025f3                csrr    x11,mepc
        80000024:   00458593                addi    x11,x11,4
        80000028:   34159073                csrw    mepc,x11
        8000002c:   001a0a13                addi    x20,x20,1
        80000030:   30200073                mret
    )objdump");

    run_until(0x80000018);

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
        80000000:   00000097                auipc   x1,0x0
        80000004:   02008093                addi    x1,x1,32 # 0x20
        80000008:   30509073                csrw    mtvec,x1
        8000000c:   00200113                li      x2,2
        80000010:   00200073                uret
        80000014:   00200073                uret
        80000018:   00300193                li      x3,3
        8000001c:   0000006f                j       0x1c
        80000020:   00a00513                li      x10,10
        80000024:   341025f3                csrr    x11,mepc
        80000028:   00458593                addi    x11,x11,4
        8000002c:   34159073                csrw    mepc,x11
        80000030:   001a0a13                addi    x20,x20,1
        80000034:   30200073                mret
    )objdump");

    run_until(0x8000001c);

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
         80000000:   0000006f                j       0x0
         80000004:   00200073                uret
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
        80000000:   00000097                auipc   x1,0x0
        80000004:   03008093                addi    x1,x1,48 # 0x30
        80000008:   30509073                csrw    mtvec,x1
        8000000c:   00000097                auipc   x1,0x0
        80000010:   01c08093                addi    x1,x1,28 # 0x28
        80000014:   00308093                addi    x1,x1,3
        80000018:   000080e7                jalr    x1
        8000001c:   00100113                li      x2,1
        80000020:   0000006f                j       0x20
        80000024:   00300193                li      x3,3
        80000028:   00400213                li      x4,4
        8000002c:   0000006f                j       0x2c
        80000030:   00a00513                li      x10,10
        80000034:   341025f3                csrr    x11,mepc
        80000038:   00458593                addi    x11,x11,4
        8000003c:   34159073                csrw    mepc,x11
        80000040:   001a0a13                addi    x20,x20,1
        80000044:   30200073                mret
    )objdump");

    run_until(0x80000020);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVEC), 0x80000030);
    EXPECT_EQ(tracer->read_reg(2), 1);
    EXPECT_EQ(tracer->read_reg(4), 0);
    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_reg(20), 1);
}

TEST_F(RXVCoreEmulWrapperTest, FENCE)
{
    load(R"objdump(
         80000000:   0ff0000f                fence
         80000004:   0a50000f                fence   ir,ow
         80000008:   00100093                li      x1,1
    )objdump");

    execute_n_instructions(3);

    EXPECT_EQ(tracer->read_reg(1), 1);
}

TEST_F(RXVCoreEmulWrapperTest, WFI)
{
    load(R"objdump(
         80000000:   10500073                wfi
         80000004:   10500073                wfi
         80000008:   00100093                li      x1,1
    )objdump");

    execute_n_instructions(3);

    EXPECT_EQ(tracer->read_reg(1), 1);
}

TEST_F(RXVCoreEmulWrapperTest, ECALL)
{
    load(R"objdump(
         80000000:   00000097                auipc   x1,0x0
         80000004:   01408093                addi    x1,x1,20 # 0x14
         80000008:   30509073                csrw    mtvec,x1
         8000000c:   00000073                ecall
         80000010:   0000006f                j       0x10
         80000014:   00a00513                li      x10,10
    )objdump");

    run_until(0x80000014);

    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x0000000b);
}

TEST_F(RXVCoreEmulWrapperTest, EBREAK)
{
    load(R"objdump(
        80000000:   00000097                auipc   x1,0x0
        80000004:   01408093                addi    x1,x1,20 # 0x14
        80000008:   30509073                csrw    mtvec,x1
        8000000c:   00100073                ebreak
        80000010:   0000006f                j       0x10
        80000014:   00a00513                li      x10,10
    )objdump");

    run_until(0x80000014);

    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x00000003);
}

TEST_F(RXVCoreEmulWrapperTest, PMU)
{
    load(R"objdump(
        80000000:   b00020f3                csrr    x1,mcycle
        80000004:   b8002173                csrr    x2,mcycleh
        80000008:   00a00513                li      x10,10
        8000000c:   00158593                addi    x11,x11,1
        80000010:   fea5cee3                blt     x11,x10,0xc
        80000014:   b00021f3                csrr    x3,mcycle
        80000018:   b8002273                csrr    x4,mcycleh
        8000001c:   b02022f3                csrr    x5,minstret
        80000020:   b8202373                csrr    x6,minstreth
    )objdump");

    run_until(0x80000020);

    EXPECT_NE(tracer->read_reg(1), 0);
    EXPECT_EQ(tracer->read_reg(2), 0);
    EXPECT_NE(tracer->read_reg(3), 0);
    EXPECT_EQ(tracer->read_reg(4), 0);
    EXPECT_NE(tracer->read_reg(5), 0);
    EXPECT_EQ(tracer->read_reg(6), 0);

    EXPECT_NE(tracer->read_reg(1), tracer->read_reg(3));
    EXPECT_EQ(tracer->read_reg(5), 25);
}

TEST_F(RXVCoreEmulWrapperTest, PMUWrite)
{
    load(R"objdump(
        80000000:   fff00093                li      x1,-1
        80000004:   b8209073                csrw    minstreth,x1
        80000008:   b8009073                csrw    mcycleh,x1
        8000000c:   b8202173                csrr    x2,minstreth
        80000010:   b80021f3                csrr    x3,mcycleh
    )objdump");

    run_until(0x80000010);

    EXPECT_EQ(tracer->read_reg(2), 0xffffffff);
    EXPECT_EQ(tracer->read_reg(3), 0xffffffff);
}

TEST_F(RXVCoreEmulWrapperTest, StoreWord)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       0020a023                sw      x2,0(x1) # 0x80001000
        80000010:       00000013                nop
    )objdump");

    run_until(0x80000010);
}

TEST_F(RXVCoreEmulWrapperTest, LoadWord)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       0000a103                lw      x2,0(x1) # 0x80001000
        80000010:       00000013                nop
    )objdump");
    bus->write(0x80001000, 0xdeadbeef, 0xf);

    for (int i = 0; i < 512 && tracer->get_last_pc() != 0x80000010; ++i) {
        cycle();
        if (i == 511)
            FAIL() << "failed to complete test";
    }

    EXPECT_EQ(tracer->read_reg(2), 0xdeadbeef);
}

TEST_F(RXVCoreEmulWrapperTest, LoadByteSigned)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       00108103                lb      x2,1(x1) # 0x80001001
        80000010:       00000013                nop
    )objdump");
    bus->write(0x80001000, 0x0000c000, 0xf);
    run_until(0x80000010);

    EXPECT_EQ(tracer->read_reg(2), 0xffffffc0);
}

TEST_F(RXVCoreEmulWrapperTest, LoadByteUnsigned)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       0010c103                lbu     x2,1(x1) # 0x80001001
        80000010:       00000013                nop
    )objdump");
    bus->write(0x80001000, 0x0000c000, 0xf);
    run_until(0x80000010);

    EXPECT_EQ(tracer->read_reg(2), 0x000000c0);
}

TEST_F(RXVCoreEmulWrapperTest, BackToBackReads)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       0000a103                lw      x2,0(x1) # 0x80001000
        80000010:       0040a183                lw      x3,4(x1)
        80000014:       00000013                nop
    )objdump");
    bus->write(0x80001000, 0xdeadbeef, 0xf);
    bus->write(0x80001004, 0xaa55a5a5, 0xf);

    run_until(0x80000014);

    EXPECT_EQ(tracer->read_reg(2), 0xdeadbeef);
    EXPECT_EQ(tracer->read_reg(3), 0xaa55a5a5);
}

TEST_F(RXVCoreEmulWrapperTest, StoreByte)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       00208023                sb      x2,0(x1) # 0x80001000
        80000010:       00000013                nop
    )objdump");

    run_until(0x80000010);
}

TEST_F(RXVCoreEmulWrapperTest, StoreWordUncached)
{
    load(R"objdump(
        80000000:       f00000b7                lui     x1,0xf0000
        80000004:       aa55a137                lui     x2,0xaa55a
        80000008:       5a510113                addi    x2,x2,1445 # 0xaa55a5a5
        8000000c:       0020a023                sw      x2,0(x1) # 0xf0000000
        80000010:       00000013                nop
    )objdump");
    bus->add_peripheral(std::make_unique<NCPeripheral>(0xf0000000, 4096));

    run_until(0x80000010);

    EXPECT_EQ(bus->read(0xf0000000), 0xaa55a5a5);
}

TEST_F(RXVCoreEmulWrapperTest, LoadUnalignedExcepts)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02008093                addi    x1,x1,32 # 0x80000020
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       800010b7                lui     x1,0x80001
        80000010:       deadc137                lui     x2,0xdeadc
        80000014:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        80000018:       0010a103                lw      x2,1(x1) # 0x80001001
        8000001c:       00a00513                li      x10,10
        80000020:       00b00593                li      x11,11
        80000024:       00000013                nop
    )objdump");

    run_until(0x80000024);

    EXPECT_EQ(tracer->read_reg(10), 0);
    EXPECT_EQ(tracer->read_reg(11), 11);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), 0x4);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000018);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0x80001001);
}

TEST_F(RXVCoreEmulWrapperTest, OOOCompletion)
{
    load(R"objdump(
        80000000:       800010b7                lui     x1,0x80001
        80000004:       deadc137                lui     x2,0xdeadc
        80000008:       eef10113                addi    x2,x2,-273 # 0xdeadbeef
        8000000c:       0000a103                lw      x2,0(x1) # 0x80001000
        80000010:       00118193                addi    x3,x3,1
        80000014:       00118193                addi    x3,x3,1
        80000018:       0080006f                j       0x80000020
        8000001c:       00120213                addi    x4,x4,1 # 0x1
        80000020:       00118193                addi    x3,x3,1
        80000024:       00000013                nop
    )objdump");
    bus->write(0x80001000, 0xf00ff00f, 0xf);

    run_until(0x80000024);

    EXPECT_EQ(tracer->read_reg(3), 3);
    EXPECT_EQ(tracer->read_reg(4), 0);
    EXPECT_EQ(tracer->read_reg(2), 0xf00ff00f);
}

TEST_F(RXVCoreEmulWrapperTest, FenceI)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02808093                addi    x1,x1,40 # 0x80000028
        80000008:       00000117                auipc   x2,0x0
        8000000c:       02410113                addi    x2,x2,36 # 0x8000002c
        80000010:       00012183                lw      x3,0(x2)
        80000014:       00000013                nop
        80000018:       00000013                nop
        8000001c:       00000013                nop
        80000020:       0030a023                sw      x3,0(x1)
        80000024:       0000100f                fence.i
        80000028:       00a00513                li      x10,10
        8000002c:       fff00513                li      x10,-1
    )objdump");

    run_until(0x80000028);

    EXPECT_EQ(tracer->read_reg(10), 0xffffffff);
}

TEST_F(RXVCoreEmulWrapperTest, IllegalCSR)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01c08093                addi    x1,x1,28 # 0x8000001c
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       00200113                li      x2,2
        80000010:       fff02573                csrr    x10,0xfff
        80000014:       00300193                li      x3,3
        80000018:       0000006f                j       0x80000018
        8000001c:       00a00513                li      x10,10
        80000020:       341025f3                csrr    x11,mepc
        80000024:       00458593                addi    x11,x11,4
        80000028:       34159073                csrw    mepc,x11
        8000002c:       001a0a13                addi    x20,x20,1
        80000030:       30200073                mret
    )objdump");

    run_until(0x8000002c);

    EXPECT_EQ(tracer->read_reg(2), 2);
    EXPECT_EQ(tracer->read_reg(3), 0);
    EXPECT_EQ(tracer->read_reg(10), 10);
}

TEST_F(RXVCoreEmulWrapperTest, SimultaneousLSUIntCompletion)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       06408093                addi    x1,x1,100 # 0x80000064
        80000008:       0000b137                lui     x2,0xb
        8000000c:       a5510113                addi    x2,x2,-1451 # 0xaa55
        80000010:       0000f1b7                lui     x3,0xf
        80000014:       00f18193                addi    x3,x3,15 # 0xf00f
        80000018:       00209023                sh      x2,0(x1)
        8000001c:       00309123                sh      x3,2(x1)
        80000020:       00120213                addi    x4,x4,1 # 0x1
        80000024:       00120213                addi    x4,x4,1 # 0x1
        80000028:       00120213                addi    x4,x4,1 # 0x1
        8000002c:       00120213                addi    x4,x4,1 # 0x1
        80000030:       00120213                addi    x4,x4,1 # 0x1
        80000034:       00120213                addi    x4,x4,1 # 0x1
        80000038:       00120213                addi    x4,x4,1 # 0x1
        8000003c:       00120213                addi    x4,x4,1 # 0x1
        80000040:       00120213                addi    x4,x4,1 # 0x1
        80000044:       00120213                addi    x4,x4,1 # 0x1
        80000048:       00120213                addi    x4,x4,1 # 0x1
        8000004c:       00120213                addi    x4,x4,1 # 0x1
        80000050:       00120213                addi    x4,x4,1 # 0x1
        80000054:       00120213                addi    x4,x4,1 # 0x1
        80000058:       00120213                addi    x4,x4,1 # 0x1
        8000005c:       00120213                addi    x4,x4,1 # 0x1
        80000060:       fb9ff06f                j       0x80000018
    )objdump");

    run_until(0x80000060);

    EXPECT_EQ(tracer->read_reg(4), 16);
}

TEST_F(RXVCoreEmulWrapperTest, Mul)
{
    load(R"objdump(
        80000000:       00300093                li      x1,3
        80000004:       00600113                li      x2,6
        80000008:       022081b3                mul     x3,x1,x2
        8000000c:       00118213                addi    x4,x3,1
    )objdump");

    run_until(0x8000000c);

    EXPECT_EQ(tracer->read_reg(3), 18);
    EXPECT_EQ(tracer->read_reg(4), 19);
}

TEST_F(RXVCoreEmulWrapperTest, Div)
{
    load(R"objdump(
        80000000:       00c00093                li      x1,12
        80000004:       00600113                li      x2,6
        80000008:       0220c1b3                div     x3,x1,x2
        8000000c:       00118213                addi    x4,x3,1
    )objdump");

    run_until(0x8000000c);

    EXPECT_EQ(tracer->read_reg(3), 2);
    EXPECT_EQ(tracer->read_reg(4), 3);
}

TEST_F(RXVCoreEmulWrapperTest, misa)
{
    load(R"objdump(
        80000000:       301020f3                csrr    x1,misa
        80000004:       00000013                nop
    )objdump");

    run_until(0x80000004);

    EXPECT_EQ(tracer->read_reg(1), (1 << 30) | (1 << 20) | (1 << 18) |
                                       (1 << 12) | (1 << 8) | (1 << 0));
}

TEST_F(RXVCoreEmulWrapperTest, amoadd)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01808093                addi    x1,x1,20 # 0x80000018
        80000008:       00100113                li      x2,1
        8000000c:       0020a1af                amoadd.w        x3,x2,(x1)
        80000010:       0000a203                lw      x4,0(x1)
        80000014:       00000013                nop
        80000018:       00010002                XXX
    )objdump");

    run_until(0x80000014);

    EXPECT_EQ(tracer->read_reg(1), 0x80000018);
    EXPECT_EQ(tracer->read_reg(2), 1);
    EXPECT_EQ(tracer->read_reg(3), 0x00010002);
    EXPECT_EQ(tracer->read_reg(4), 0x00010003);
}

TEST_F(RXVCoreEmulWrapperTest, AMORegFree)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02008093                addi    x1,x1,32 # 0x80000020
        80000008:       00100113                li      x2,1
        8000000c:       10000293                li      x5,256
        80000010:       0020a1af                amoadd.w        x3,x2,(x1)
        80000014:       00120213                addi    x4,x4,1 # 0x1
        80000018:       fe524ce3                blt     x4,x5,0x80000010
        8000001c:       00000013                nop
    )objdump");

    run_until(0x8000001c);

    EXPECT_EQ(tracer->read_reg(3), 255);
    EXPECT_EQ(tracer->read_reg(4), 256);
}

TEST_F(RXVCoreEmulWrapperTest, AMOSwap)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01c08093                addi    x1,x1,28 # 0x8000001c
        80000008:       12345137                lui     x2,0x12345
        8000000c:       67810113                addi    x2,x2,1656 # 0x12345678
        80000010:       0820a1af                amoswap.w       x3,x2,(x1)
        80000014:       0000a203                lw      x4,0(x1)
        80000018:       00000013                nop
        8000001c:       aa55a5a5                0xaa55a5a5
    )objdump");

    run_until(0x80000018);

    EXPECT_EQ(tracer->read_reg(3), 0xaa55a5a5);
    EXPECT_EQ(tracer->read_reg(4), 0x12345678);
}

TEST_F(RXVCoreEmulWrapperTest, AMOX0)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01408093                addi    x1,x1,20 # 0x80000014
        80000008:       00100113                li      x2,1
        8000000c:       0020a02f                amoadd.w        x0,x2,(x1)
        80000010:       00000013                nop
    )objdump");

    run_until(0x80000010);
}

TEST_F(RXVCoreEmulWrapperTest, AMODeviceAborts)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01c08093                addi    x1,x1,28 # 0x8000001c
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       f00000b7                lui     x1,0xf0000
        80000010:       00100113                li      x2,1
        80000014:       0020a02f                amoadd.w        x0,x2,(x1)
        80000018:       0000006f                j       0x80000018
        8000001c:       00a00513                li      x10,10
        80000020:       341025f3                csrr    x11,mepc
        80000024:       34202673                csrr    x12,mcause
        80000028:       343026f3                csrr    x13,mtval
        8000002c:       00000013                nop
    )objdump");

    run_until(0x8000002c);

    EXPECT_EQ(tracer->read_reg(10), 10);
    EXPECT_EQ(tracer->read_reg(11), 0x80000014);
    EXPECT_EQ(tracer->read_reg(12), 7);
    EXPECT_EQ(tracer->read_reg(13), 0xf0000000);
}

TEST_F(RXVCoreEmulWrapperTest, LRSC)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       01c08093                addi    x1,x1,28 # 0x8000001c
        80000008:       1000a12f                lr.w    x2,(x1)
        8000000c:       00110113                addi    x2,x2,1
        80000010:       1820a1af                sc.w    x3,x2,(x1)
        80000014:       0000a203                lw      x4,0(x1)
        80000018:       00000013                nop
    )objdump");

    run_until(0x80000018);

    EXPECT_EQ(tracer->read_reg(2), 1);
    EXPECT_EQ(tracer->read_reg(3), 0);
    EXPECT_EQ(tracer->read_reg(4), 1);
}

TEST_F(RXVCoreEmulWrapperTest, ReservationLost)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02408093                addi    x1,x1,36 # 0x80000024
        80000008:       10008513                addi    x10,x1,256
        8000000c:       1000a12f                lr.w    x2,(x1)
        80000010:       00052583                lw      x11,0(x10)
        80000014:       00110113                addi    x2,x2,1
        80000018:       1820a1af                sc.w    x3,x2,(x1)
        8000001c:       0000a203                lw      x4,0(x1)
        80000020:       00000013                nop
    )objdump");

    run_until(0x80000020);

    EXPECT_EQ(tracer->read_reg(2), 1);
    EXPECT_EQ(tracer->read_reg(3), 1);
    EXPECT_EQ(tracer->read_reg(4), 0);
}

TEST_F(RXVCoreEmulWrapperTest, SequentialSCLosesReservation)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02408093                addi    x1,x1,36 # 0x80000024
        80000008:       1000a12f                lr.w    x2,(x1)
        8000000c:       00110113                addi    x2,x2,1
        80000010:       06410613                addi    x12,x2,100
        80000014:       1820a1af                sc.w    x3,x2,(x1)
        80000018:       18c0a22f                sc.w    x4,x12,(x1)
        8000001c:       0000a283                lw      x5,0(x1)
        80000020:       00000013                nop
    )objdump");

    run_until(0x80000020);

    EXPECT_EQ(tracer->read_reg(2), 1);
    EXPECT_EQ(tracer->read_reg(12), 101);
    EXPECT_EQ(tracer->read_reg(3), 0);
    EXPECT_EQ(tracer->read_reg(4), 1);
    EXPECT_EQ(tracer->read_reg(5), 1);
}

TEST_F(RXVCoreEmulWrapperTest, MStatusIRQStack)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02008093                addi    x1,x1,32 # 0x80000020
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       30045073                csrwi   mstatus,8
        80000010:       300020f3                csrr    x1,mstatus
        80000014:       00000073                ecall
        80000018:       30002273                csrr    x4,mstatus
        8000001c:       00000013                nop
        80000020:       30002173                csrr    x2,mstatus
        80000024:       341021f3                csrr    x3,mepc
        80000028:       00418193                addi    x3,x3,4
        8000002c:       34119073                csrw    mepc,x3
        80000030:       30200073                mret
    )objdump");

    run_until(0x8000001c);

    EXPECT_EQ(tracer->read_reg(1), 0x0008);
    EXPECT_EQ(tracer->read_reg(2), 0x1880);
    EXPECT_EQ(tracer->read_reg(4), 0x0008);
}

TEST_F(RXVCoreEmulWrapperTest, SWIRQ)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       02008093                addi    x1,x1,32 # 0x80000020
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       30045073                csrwi   mstatus,8
        80000010:       00800093                li      x1,8
        80000014:       30409073                csrw    mie,x1
        80000018:       34409073                csrw    mip,x1
        8000001c:       0000006f                j       0x8000001c
        80000020:       30002173                csrr    x2,mstatus
        80000024:       34401073                csrw    mip,x0
        80000028:       30200073                mret
    )objdump");

    execute_n_instructions(256);

    EXPECT_EQ(tracer->read_reg(2), 0x1880);
}

TEST_F(RXVCoreEmulWrapperTest, SFENCE_VMA)
{
    load(R"objdump(
        80000000:       12000073                sfence.vma
        80000004:       00000013                nop
    )objdump");

    execute_n_instructions(2);
}

TEST_F(RXVCoreEmulWrapperTest, SATPProgram)
{
    load(R"objdump(
        80000000:       800820b7                lui     x1,0x80082
        80000004:       18009073                csrw    satp,x1
        80000008:       00000117                auipc   x2,0x0
        8000000c:       01c10113                addi    x2,x2,28 # 0x80000024
        80000010:       34111073                csrw    mepc,x2
        80000014:       000011b7                lui     x3,0x1
        80000018:       80018193                addi    x3,x3,-2048 # 0x800
        8000001c:       30019073                csrw    mstatus,x3
        80000020:       30200073                mret
        80000024:       00000217                auipc   x4,0x0
        80000028:       02420213                addi    x4,x4,36 # 0x80000048
        8000002c:       80000337                lui     x6,0x80000
        80000030:       00624333                xor     x6,x4,x6
        80000034:       00022283                lw      x5,0(x4) # 0x0
        80000038:       00432383                lw      x7,4(x6) # 0x80000004
        8000003c:       00832403                lw      x8,8(x6)
        80000040:       00c32483                lw      x9,12(x6)
        80000044:       00000013                nop
        80000048:       5678                    lw      x14,108(x12)
        8000004a:       1234                    addi    x13,x2,296
        8000004c:       ced0                    sw      x12,28(x13)
        8000004e:       defa                    sw      x30,124(x2)
        80000050:       a5a5                    j       0x800006b8
        80000052:       aa55                    j       0x80000206
        80000054:       4321                    li      x6,8
        80000056:       8765                    srai    x14,x14,0x19
    )objdump");

    set_megapage_at(0x00000000, 0x80000000,
                    pte_read | pte_write | pte_exec | pte_accessed | pte_dirty);
    set_megapage_at(0x80000000, 0x80000000,
                    pte_read | pte_write | pte_exec | pte_accessed | pte_dirty);

    run_until(0x80000044);

    EXPECT_EQ(tracer->read_reg(5), 0x12345678);
    EXPECT_EQ(tracer->read_reg(7), 0xdefaced0);
    EXPECT_EQ(tracer->read_reg(8), 0xaa55a5a5);
    EXPECT_EQ(tracer->read_reg(9), 0x87654321);
}

TEST_F(RXVCoreEmulWrapperTest, PageFault)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       03c08093                addi    x1,x1,60 # 0x8000003c
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       800820b7                lui     x1,0x80082
        80000010:       18009073                csrw    satp,x1
        80000014:       00000097                auipc   x1,0x0
        80000018:       01c08093                addi    x1,x1,28 # 0x80000030
        8000001c:       34109073                csrw    mepc,x1
        80000020:       000011b7                lui     x3,0x1
        80000024:       80018193                addi    x3,x3,-2048 # 0x800
        80000028:       30019073                csrw    mstatus,x3
        8000002c:       30200073                mret
        80000030:       c00000b7                lui     x1,0xc0000
        80000034:       0000a083                lw      x1,0(x1) # 0xc0000000
        80000038:       0000006f                j       0x80000038
        8000003c:       00000013                nop
    )objdump");

    set_megapage_at(0x00000000, 0x80000000,
                    pte_read | pte_write | pte_exec | pte_accessed | pte_dirty);
    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);

    run_until(0x8000003c);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_PAGE_FAULT);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0xc0000000);
}

static const std::string s_load_store_test = R"objdump(
80000000:       00000097                auipc   x1,0x0
80000004:       04808093                addi    x1,x1,72 # 0x80000048
80000008:       30509073                csrw    mtvec,x1
8000000c:       800820b7                lui     x1,0x80082
80000010:       18009073                csrw    satp,x1
80000014:       00000097                auipc   x1,0x0
80000018:       02008093                addi    x1,x1,32 # 0x80000034
8000001c:       34109073                csrw    mepc,x1
80000020:       000011b7                lui     x3,0x1
80000024:       80018193                addi    x3,x3,-2048 # 0x800
80000028:       30019073                csrw    mstatus,x3
8000002c:       804000b7                lui     x1,0x80400
80000030:       30200073                mret
80000034:       f00ff1b7                lui     x3,0xf00ff
80000038:       00f18193                addi    x3,x3,15 # 0xf00ff00f
8000003c:       0000a103                lw      x2,0(x1) # 0x80400000
80000040:       0030a223                sw      x3,4(x1)
80000044:       0000006f                j       0x80000044
80000048:       00000013                nop
)objdump";

TEST_F(RXVCoreEmulWrapperTest, MegapageAccessOkay)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(0x80400000, 0x80400000,
                    pte_read | pte_write | pte_exec | pte_accessed | pte_dirty);

    run_until(0x80000044);

    EXPECT_EQ(tracer->read_reg(2), 0xf00ff1b7);
}

TEST_F(RXVCoreEmulWrapperTest, PageAccessOkay)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_page_at(0x80400000, 0x80400000,
                pte_read | pte_write | pte_exec | pte_accessed | pte_dirty);

    run_until(0x80000044);

    EXPECT_EQ(tracer->read_reg(2), 0xf00ff1b7);
}

TEST_F(RXVCoreEmulWrapperTest, NotAccessedMegapageFaults)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(0x80400000, 0x80400000,
                    pte_read | pte_write | pte_exec | pte_dirty);

    run_until(0x80000048);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x8000003c);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_PAGE_FAULT);
}

TEST_F(RXVCoreEmulWrapperTest, NotAccessedPageFaults)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_page_at(0x80400000, 0x80400000,
                pte_read | pte_write | pte_exec | pte_dirty);

    run_until(0x80000048);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x8000003c);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_PAGE_FAULT);
}

TEST_F(RXVCoreEmulWrapperTest, UserNoSUMFaults)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(
        0x80400000, 0x80400000,
        pte_read | pte_write | pte_exec | pte_accessed | pte_dirty | pte_user);

    run_until(0x80000048);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x8000003c);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_PAGE_FAULT);
}

TEST_F(RXVCoreEmulWrapperTest, CleanWriteFaults)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(0x80400000, 0x80400000,
                    pte_read | pte_write | pte_exec | pte_accessed);

    run_until(0x80000048);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000040);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), STORE_PAGE_FAULT);
}

TEST_F(RXVCoreEmulWrapperTest, ReadOnlyWriteFaults)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(0x80400000, 0x80400000,
                    pte_read | pte_exec | pte_accessed | pte_dirty);

    run_until(0x80000048);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000040);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), STORE_PAGE_FAULT);
}

TEST_F(RXVCoreEmulWrapperTest, NoReadFaults)
{
    load(s_load_store_test);

    set_megapage_at(0x80000000, 0x80000000, pte_read | pte_exec | pte_accessed);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(0x80400000, 0x80400000,
                    pte_write | pte_exec | pte_accessed | pte_dirty);

    run_until(0x80000048);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x8000003c);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_PAGE_FAULT);
}

static const std::string u_load_store_test = R"objdump(
80000000:       00000097                auipc   x1,0x0
80000004:       03c08093                addi    x1,x1,60 # 0x8000003c
80000008:       30509073                csrw    mtvec,x1
8000000c:       800820b7                lui     x1,0x80082
80000010:       18009073                csrw    satp,x1
80000014:       00000097                auipc   x1,0x0
80000018:       01408093                addi    x1,x1,20 # 0x80000028
8000001c:       34109073                csrw    mepc,x1
80000020:       804000b7                lui     x1,0x80400
80000024:       30200073                mret
80000028:       f00ff1b7                lui     x3,0xf00ff
8000002c:       00f18193                addi    x3,x3,15 # 0xf00ff00f
80000030:       0000a103                lw      x2,0(x1) # 0x80400000
80000034:       0030a223                sw      x3,4(x1)
80000038:       0000006f                j       0x80000038
8000003c:       00000013                nop
)objdump";

TEST_F(RXVCoreEmulWrapperTest, UserMegapageAccessOkay)
{
    load(u_load_store_test);

    set_megapage_at(0x80000000, 0x80000000,
                    pte_read | pte_exec | pte_accessed | pte_user);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(
        0x80400000, 0x80400000,
        pte_read | pte_write | pte_exec | pte_accessed | pte_dirty | pte_user);

    run_until(0x80000038);

    EXPECT_EQ(tracer->read_reg(2), 0xf00ff1b7);
}

TEST_F(RXVCoreEmulWrapperTest, UserSupervisorAccessFaults)
{
    load(u_load_store_test);

    set_megapage_at(0x80000000, 0x80000000,
                    pte_read | pte_exec | pte_accessed | pte_user);
    bus->write(0x80400000, 0xf00ff1b7, 0xf);
    set_megapage_at(0x80400000, 0x80400000,
                    pte_read | pte_write | pte_exec | pte_accessed | pte_dirty);

    run_until(0x8000003c);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000030);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_PAGE_FAULT);
}

TEST_F(RXVCoreEmulWrapperTest, InstructionPageFault)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       03008093                addi    x1,x1,48 # 0x80000030
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       800820b7                lui     x1,0x80082
        80000010:       18009073                csrw    satp,x1
        80000014:       00000097                auipc   x1,0x0
        80000018:       01408093                addi    x1,x1,20 # 0x80000028
        8000001c:       34109073                csrw    mepc,x1
        80000020:       804000b7                lui     x1,0x80400
        80000024:       30200073                mret
        80000028:       c00001b7                lui     x3,0xc0000
        8000002c:       00018067                jr      x3 # 0xc0000000
        80000030:       00000013                nop
    )objdump");

    set_megapage_at(0x80000000, 0x80000000,
                    pte_read | pte_exec | pte_accessed | pte_user);

    run_until(0x80000030);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE),
              INSTRUCTION_PAGE_FAULT);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0xc0000000);
}

TEST_F(RXVCoreEmulWrapperTest, PMPDeny)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       05008093                addi    x1,x1,80 # 0x80000050
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       80401137                lui     x2,0x80401
        80000010:       00012183                lw      x3,0(x2) # 0x80401000
        80000014:       201800b7                lui     x1,0x20180
        80000018:       fff08093                addi    x1,x1,-1 # 0x2017ffff
        8000001c:       3b009073                csrw    pmpaddr0,x1
        80000020:       01800093                li      x1,24
        80000024:       3a009073                csrw    pmpcfg0,x1
        80000028:       12000073                sfence.vma
        8000002c:       000011b7                lui     x3,0x1
        80000030:       80018193                addi    x3,x3,-2048 # 0x800
        80000034:       30019073                csrw    mstatus,x3
        80000038:       00000197                auipc   x3,0x0
        8000003c:       01018193                addi    x3,x3,16 # 0x80000048
        80000040:       34119073                csrw    mepc,x3
        80000044:       30200073                mret
        80000048:       00012203                lw      x4,0(x2)
        8000004c:       0000006f                j       0x8000004c
        80000050:       341025f3                csrr    x11,mepc
        80000054:       34202673                csrr    x12,mcause
        80000058:       0000006f                j       0x80000058
    )objdump");

    run_until(0x80000058);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), LOAD_ACCESS_FAULT);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0x80401000);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000048);
}

TEST_F(RXVCoreEmulWrapperTest, PMPExecDeny)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       05008093                addi    x1,x1,80 # 0x80000050
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       80401137                lui     x2,0x80401
        80000010:       00012183                lw      x3,0(x2) # 0x80401000
        80000014:       201800b7                lui     x1,0x20180
        80000018:       fff08093                addi    x1,x1,-1 # 0x2017ffff
        8000001c:       3b009073                csrw    pmpaddr0,x1
        80000020:       01800093                li      x1,24
        80000024:       3a009073                csrw    pmpcfg0,x1
        80000028:       12000073                sfence.vma
        8000002c:       000011b7                lui     x3,0x1
        80000030:       80018193                addi    x3,x3,-2048 # 0x800
        80000034:       30019073                csrw    mstatus,x3
        80000038:       00000197                auipc   x3,0x0
        8000003c:       01018193                addi    x3,x3,16 # 0x80000048
        80000040:       34119073                csrw    mepc,x3
        80000044:       30200073                mret
        80000048:       00010067                jr      x2
        8000004c:       0000006f                j       0x8000004c
        80000050:       341025f3                csrr    x11,mepc
        80000054:       34202673                csrr    x12,mcause
        80000058:       0000006f                j       0x80000058
    )objdump");

    run_until(0x80000058);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE), INSTR_ACCESS_FAULT);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0x80401000);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80401000);
}

TEST_F(RXVCoreEmulWrapperTest, PMPMMUDeny)
{
    load(R"objdump(
        80000000:       00000097                auipc   x1,0x0
        80000004:       06008093                addi    x1,x1,96 # 0x80000060
        80000008:       30509073                csrw    mtvec,x1
        8000000c:       80401137                lui     x2,0x80401
        80000010:       00012183                lw      x3,0(x2) # 0x80401000
        80000014:       240000b7                lui     x1,0x24000
        80000018:       fff08093                addi    x1,x1,-1 # 0x23ffffff
        8000001c:       3b009073                csrw    pmpaddr0,x1
        80000020:       01800093                li      x1,24
        80000024:       3a009073                csrw    pmpcfg0,x1
        80000028:       12000073                sfence.vma
        8000002c:       000011b7                lui     x3,0x1
        80000030:       80018193                addi    x3,x3,-2048 # 0x800
        80000034:       30019073                csrw    mstatus,x3
        80000038:       00c15113                srli    x2,x2,0xc
        8000003c:       80000237                lui     x4,0x80000
        80000040:       00416133                or      x2,x2,x4
        80000044:       18011073                csrw    satp,x2
        80000048:       00000197                auipc   x3,0x0
        8000004c:       01018193                addi    x3,x3,16 # 0x80000058
        80000050:       34119073                csrw    mepc,x3
        80000054:       30200073                mret
        80000058:       00000013                nop
        8000005c:       0000006f                j       0x8000005c
        80000060:       341025f3                csrr    x11,mepc
        80000064:       34202673                csrr    x12,mcause
        80000068:       0000006f                j       0x80000068
    )objdump");

    run_until(0x80000064);

    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MCAUSE),
              INSTRUCTION_PAGE_FAULT);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MTVAL), 0x80000058);
    EXPECT_EQ(tracer->read_csr(RXV::Trace::CSRId_MEPC), 0x80000058);
}

TEST_F(RXVCoreEmulWrapperTest, BranchCounts)
{
    load(R"objdump(
80000000:       00300093                li      x1,3
80000004:       32309073                csrw    mhpmevent3,x1
80000008:       00400093                li      x1,4
8000000c:       32409073                csrw    mhpmevent4,x1
80000010:       ff700093                li      x1,-9
80000014:       b0309073                csrw    mhpmcounter3,x1
80000018:       fff00093                li      x1,-1
8000001c:       b8309073                csrw    mhpmcounter3h,x1
80000020:       01000113                li      x2,16
80000024:       000001b3                add     x3,x0,x0
80000028:       00118193                addi    x3,x3,1
8000002c:       fe219ee3                bne     x3,x2,0x80000028
80000030:       b0302273                csrr    x4,mhpmcounter3
80000034:       b04022f3                csrr    x5,mhpmcounter4
80000038:       00000013                nop
    )objdump");

    run_until(0x80000038);
}