#include "VerilogTestbench.h"
#include "VRXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_RXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_BusTransactor.h"
#include "MemoryDevice.h"
#include "MockMemoryBus.h"

class RXVCoreEmulWrapperTest
    : public VerilogTestbench<VRXVCoreEmulWrapper>
    , public ::testing::Test
{
public:
    RXVCoreEmulWrapperTest()
    {
        reset();
        bus = std::make_shared<MemoryBus>(0x80000000, 64 * 1024);
        this->dut.RXVCoreEmulWrapper->IBusTransactor->set_bus(bus);
        this->dut.RXVCoreEmulWrapper->DBusTransactor->set_bus(bus);
    }

    std::shared_ptr<MemoryBus> bus;
};

TEST_F(RXVCoreEmulWrapperTest, InstructionFetches)
{
    bus->write(0x80000000, 0xdeadbeef, 0xf);
    bus->write(0x80000004, 0xf00facdc, 0xf);

    cycle(128);
}
