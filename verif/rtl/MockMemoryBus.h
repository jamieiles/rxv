#pragma once
#include <stdint.h>
#include <gmock/gmock.h>

class MockMemoryBus : public AbstractMemoryBus
{
public:
    MOCK_METHOD(void, read, (uint32_t addr, char *dst, size_t len), (override));
    MOCK_METHOD(void,
                write,
                (uint32_t addr, const char *val, size_t len),
                (override));
    MOCK_METHOD(void,
                write,
                (uint32_t addr, uint32_t val, uint8_t wstb),
                (override));
    MOCK_METHOD(uint32_t, read, (uint32_t addr), (override));
    MOCK_METHOD(void,
                add_peripheral,
                (std::unique_ptr<IOPeripheral> p),
                (override));
};