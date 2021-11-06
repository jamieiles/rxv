`systemc_header
#include <memory>
#include "MemoryDevice.h"
`systemc_interface
std::shared_ptr<AbstractMemoryBus> bus;
void set_bus(std::shared_ptr<AbstractMemoryBus> bus)
{
    this->bus = bus;
}
`verilog
