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

class TestbenchTracer : public SimTracer
{
public:
    TestbenchTracer(const std::optional<std::string> filename)
        : SimTracer(filename), num_instructions(0), last_pc(0x80000000)
    {
        for (auto i = 0; i < 32; ++i)
            shadow_regs[i] = 0;
    }

    virtual void trace_write_reg(int id, int r, uint32_t v) override
    {
        SimTracer::trace_write_reg(id, r, v);
        shadow_regs[r] = v;
    }

    virtual void trace_write_csr(int id, int r, uint32_t v) override
    {
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
        pc_map[id] = pc;
    }

    virtual void trace_exception(int id) override
    {
        SimTracer::trace_exception(id);
    }

    virtual void trace_end_instruction(int id) override
    {
        SimTracer::trace_end_instruction(id);
        ++num_instructions;
        last_pc = pc_map[id];
    }

    uint32_t read_reg(int id) const
    {
        if (id < 0 || id >= 32)
            throw std::runtime_error("invalid GPR");

        return shadow_regs[id];
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
    int num_instructions;
    uint32_t last_pc;
    std::map<int, uint32_t> pc_map;
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