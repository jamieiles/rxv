// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
#include <memory>
#include <cstring>
#include "svdpi.h"
#include "MemoryDevice.h"

#include "VBusTransactorWrapper__Dpi.h"

extern "C" uint32_t bus_read(void *handle,
                             const svBitVecVal *address,
                             svBit instruction)
{
    MemoryBus *bus = static_cast<MemoryBus *>(handle);

    return bus->read(*address, instruction);
}

extern "C" void bus_write(void *handle,
                          const svBitVecVal *address,
                          const svBitVecVal *data,
                          const svBitVecVal *wstb)
{
    MemoryBus *bus = static_cast<MemoryBus *>(handle);

    bus->write(*address, *data, *wstb);
}