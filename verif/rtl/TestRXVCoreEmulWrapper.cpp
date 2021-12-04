#include <iostream>
#include <iterator>
#include <sstream>
#include <vector>
#include <algorithm>

#include "VerilogTestbench.h"
#include "VRXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_RXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_BusTransactor.h"
#include "VRXVCoreEmulWrapper_RXVCore.h"
#include "MemoryDevice.h"
#include "MockMemoryBus.h"
#include "SimTracer.h"

class RXVCoreEmulWrapperTest
    : public VerilogTestbench<VRXVCoreEmulWrapper>
    , public ::testing::Test
{
public:
    RXVCoreEmulWrapperTest()
    {
        this->dut.RXVCoreEmulWrapper->RXVCore->tracer =
            std::make_unique<SimTracer>(current_test_name() + ".trace");
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

    cycle(512);
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

    cycle(512);
}

TEST_F(RXVCoreEmulWrapperTest, NoBypassX0)
{
    load(R"objdump(
         0:   00108093                addi    x0,x0,1
         4:   00108093                addi    x0,x0,1
         8:   00108093                addi    x0,x0,1
         c:   00108093                addi    x0,x0,1
        10:   000080b3                add     x1,x1,x0
    )objdump");

    cycle(512);
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

    cycle(512);
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

    cycle(512);
}