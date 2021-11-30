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
    for (int i = 0; i < 2; ++i)
        bus->write(0x80000000 + i * 4, 0x00418133, 0xf);
    bus->write(0x80000000 + 8, 0x00210133, 0xf);
    bus->write(0x80000000 + 12, 0x40518233, 0xf);
    bus->write(0x80000000 + 16, 0x00418133, 0xf);
    for (int i = 0; i < 128; ++i)
        bus->write(0x80000000 + 20 + i * 4, 0x00418133, 0xf);

    cycle(512);
}
