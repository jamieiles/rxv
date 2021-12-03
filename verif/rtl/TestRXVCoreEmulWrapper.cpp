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

    std::shared_ptr<MemoryBus> bus;
};

TEST_F(RXVCoreEmulWrapperTest, InstructionFetches)
{
    /*
     *  0:   00000093                li      x1,0
     *  4:   00a00113                li      x2,10
     *  8:   00108093                addi    x1,x1,1
     *  c:   fe20cee3                blt     x1,x2,0x8
     * 10:   0f000513                li      x10,240
     * 14:   000005ef                jal     x11,0x14
     */
    bus->write(0x80000000, 0x00000093, 0xf);
    bus->write(0x80000004, 0x00a00113, 0xf);
    bus->write(0x80000008, 0x00108093, 0xf);
    bus->write(0x8000000c, 0xfe20cee3, 0xf);
    bus->write(0x80000010, 0x0f000513, 0xf);
    bus->write(0x80000014, 0x000005ef, 0xf);

    cycle(512);
}

TEST_F(RXVCoreEmulWrapperTest, ALUBypass)
{
    /*
     *  0:   00108093                addi    x1,x1,1
     *     ...
     */
    for (int i = 0; i < 16; ++i)
        bus->write(0x80000000 + i * 4, 0x00108093, 0xf);

    cycle(512);
}

TEST_F(RXVCoreEmulWrapperTest, NoBypassX0)
{
    /*
     *  0:   00108093                addi    x0,x0,1
     *     ...
     */
    for (int i = 0; i < 16; ++i)
        bus->write(0x80000000 + i * 4, 0x00100013, 0xf);
    bus->write(0x80000000 + 16 * 4, 0x000080b3, 0xf);

    cycle(512);
}

TEST_F(RXVCoreEmulWrapperTest, JALR)
{
    /*
     *  0:   00100093                li      x1,1
     *  4:   00c000ef                jal     x1,0x10
     *  8:   0dc00193                li      x3,220
     *  c:   0000006f                j       0xc
     * 10:   0ac00113                li      x2,172
     * 14:   00008067                ret
     */
    bus->write(0x80000000, 0x00100093, 0xf);
    bus->write(0x80000004, 0x00c000ef, 0xf);
    bus->write(0x80000008, 0x0dc00193, 0xf);
    bus->write(0x8000000c, 0x0000006f, 0xf);
    bus->write(0x80000010, 0x0ac00113, 0xf);
    bus->write(0x80000014, 0x00008067, 0xf);

    cycle(512);
}

TEST_F(RXVCoreEmulWrapperTest, BackToBackJumps)
{
    /*
     *  0:   0040006f                j       0x4
     *  4:   0040006f                j       0x8
     *  8:   0040006f                j       0xc
     *  c:   00150513                addi    x10,x10,1
     * 10:   ff1ff06f                j       0x0
     */
    bus->write(0x80000000, 0x0040006f, 0xf);
    bus->write(0x80000004, 0x0040006f, 0xf);
    bus->write(0x80000008, 0x0040006f, 0xf);
    bus->write(0x8000000c, 0x00150513, 0xf);
    bus->write(0x80000010, 0xff1ff06f, 0xf);

    cycle(512);
}