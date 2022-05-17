#pragma once

#include <stdint.h>
#include <cstddef>
#include <vector>
#include <cstdlib>
#include <cassert>

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
    virtual void read(uint32_t addr,
                      char *dst,
                      size_t len,
                      bool instruction_fetch) = 0;
    virtual void write(uint32_t addr, const char *val, size_t len) = 0;
    virtual void write(uint32_t addr, uint32_t val, uint8_t wstb) = 0;
    virtual uint32_t read(uint32_t addr, bool instruction_fetch) = 0;
    virtual void add_peripheral(std::unique_ptr<IOPeripheral> p) = 0;
};

class MemoryBus : public AbstractMemoryBus
{
public:
    MemoryBus(uint32_t ram_base, size_t ram_size, bool log_unmapped = true)
        : ram_base(ram_base), ram_size(ram_size), log_unmapped(log_unmapped)
    {
        mem = std::make_unique<uint32_t[]>(ram_size / 4);
    }

    virtual void read(uint32_t addr,
                      char *dst,
                      size_t len,
                      bool instruction_fetch = false)
    {
        if (addr >= ram_base && addr < ram_base + ram_size) {
            addr -= ram_base;
            if (addr + len > ram_size)
                throw MemFault("Out of bounds memory access");

            memcpy(dst, reinterpret_cast<uint8_t *>(mem.get()) + addr, len);
        } else if (!instruction_fetch) {
            peripheral_read(addr, dst, len);
        }
    }

    virtual void write(uint32_t addr, const char *val, size_t len)
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

    virtual void write(uint32_t addr, uint32_t val, uint8_t wstb)
    {
        auto byte_offs = __builtin_ffs(wstb) - 1;
        auto nbytes = __builtin_popcount(wstb);
        auto byte_ptr = reinterpret_cast<const char *>(&val) + byte_offs;

        write(addr, byte_ptr, nbytes);
    }

    virtual uint32_t read(uint32_t addr, bool instruction_fetch = false)
    {
        uint32_t v = 0;

        read(addr, reinterpret_cast<char *>(&v), sizeof(v), instruction_fetch);

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

        if (log_unmapped)
            throw std::runtime_error("invalid write to   " +
                                     std::to_string(addr));
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

        if (log_unmapped)
            throw std::runtime_error("invalid read from " +
                                     std::to_string(addr));
    }

private:
    uint32_t ram_base;
    size_t ram_size;
    std::unique_ptr<uint32_t[]> mem;
    std::vector<std::unique_ptr<IOPeripheral>> peripherals;
    bool log_unmapped;
};
