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
     * 10:   00108093                addi    x1,x1,1
     * 14:   0000006f                j       0x10
     */
    bus->write(0x80000000, 0x00000093, 0xf);
    bus->write(0x80000004, 0x00a00113, 0xf);
    bus->write(0x80000008, 0x00108093, 0xf);
    bus->write(0x8000000c, 0xfe20cee3, 0xf);
    bus->write(0x80000010, 0x00108093, 0xf);
    bus->write(0x80000014, 0x0000006f, 0xf);

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