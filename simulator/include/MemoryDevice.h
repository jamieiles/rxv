#pragma once

#include <stdint.h>
#include <cstddef>

using MemFault = std::runtime_error;

class IOPeripheral
{
public:
    IOPeripheral(uint32_t base, size_t len) : base(base), len(len)
    {
    }

    virtual ~IOPeripheral()
    {
    }

    virtual void write(uint32_t offset, const char *v, size_t len) = 0;
    virtual void read(uint32_t offset, char *v, size_t len) = 0;

    size_t get_len() const
    {
        return len;
    }

    uint32_t get_base() const
    {
        return base;
    }

private:
    uint32_t base;
    size_t len;
};

class AbstractMemoryBus
{
public:
    virtual void read(uint32_t addr, char *dst, size_t len) = 0;
    virtual void write(uint32_t addr, const char *val, size_t len) = 0;
    virtual void write(uint32_t addr, uint32_t val, uint8_t wstb) = 0;
    virtual uint32_t read(uint32_t addr) = 0;
    virtual void add_peripheral(std::unique_ptr<IOPeripheral> p) = 0;
};

class MemoryBus : public AbstractMemoryBus
{
public:
    MemoryBus(uint32_t ram_base, size_t ram_size)
        : ram_base(ram_base), ram_size(ram_size)
    {
        mem = std::make_unique<uint32_t[]>(ram_size / 4);
    }

    void read(uint32_t addr, char *dst, size_t len)
    {
        if (addr >= ram_base && addr < ram_base + ram_size) {
            addr -= ram_base;
            if (addr + len > ram_size)
                throw MemFault("Out of bounds memory access");

            memcpy(dst, reinterpret_cast<uint8_t *>(mem.get()) + addr, len);
        } else {
            peripheral_read(addr, dst, len);
        }
    }

    void write(uint32_t addr, const char *val, size_t len)
    {
        if (addr >= ram_base && addr < ram_base + ram_size) {
            addr -= ram_base;
            if (addr + len > ram_size)
                throw MemFault("Out of bounds memory access");

            memcpy(reinterpret_cast<uint8_t *>(mem.get()) + addr, val, len);
        } else {
            peripheral_write(addr, val, len);
        }
    }

    void write(uint32_t addr, uint32_t val, uint8_t wstb)
    {
        auto byte_offs = __builtin_ffs(wstb) - 1;
        auto nbytes = __builtin_popcount(wstb);
        auto byte_ptr = reinterpret_cast<const char *>(&val) + byte_offs;

        write(addr, byte_ptr, nbytes);
    }

    uint32_t read(uint32_t addr)
    {
        uint32_t v;

        read(addr, reinterpret_cast<char *>(&v), sizeof(v));

        return v;
    }

    void add_peripheral(std::unique_ptr<IOPeripheral> p)
    {
        peripherals.push_back(std::move(p));
    }

private:
    void peripheral_write(uint32_t addr, const char *val, size_t len)
    {
        assert(len <= sizeof(uint32_t));

        for (auto &p : peripherals) {
            if (addr < p->get_base() || addr >= p->get_base() + p->get_len())
                continue;

            p->write(addr - p->get_base(), val, len);
            return;
        }
    }

    void peripheral_read(uint32_t addr, char *val, size_t len)
    {
        assert(len <= sizeof(uint32_t));

        for (auto &p : peripherals) {
            if (addr < p->get_base() || addr >= p->get_base() + p->get_len())
                continue;

            p->read(addr - p->get_base(), val, len);
            return;
        }
    }

private:
    uint32_t ram_base;
    size_t ram_size;
    std::unique_ptr<uint32_t[]> mem;
    std::vector<std::unique_ptr<IOPeripheral>> peripherals;
};