#pragma once
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <iostream>

#include "RiscVELF.h"

using MemFault = std::runtime_error;

struct mtime {
    uint64_t time;
    uint64_t cmp;
};

class SimulatorBase
{
public:
    static constexpr char default_trace_name[] = "RXVCore.vcd";
    static constexpr size_t default_mem_size = 1024 * 1024;
    static constexpr uint32_t default_mem_base = 0x0;
    static constexpr uint32_t mtime_base = 0xffff0000;

    SimulatorBase(const std::string trace_name,
                  size_t mem_size = default_mem_size,
                  uint32_t mem_base = default_mem_base)
        : mem_size(mem_size), mem_base(mem_base)
    {
        mtime.time = mtime.cmp = 0;
        mem = std::make_unique<uint32_t[]>(mem_size / 4);
    }

    void load_elf(const RiscVELF &elf);

    template <typename T>
    T read_mem(uint32_t addr) const
    {
        if (addr >= mtime_base && addr < mtime_base + sizeof(mtime)) {
            size_t offs = addr - mtime_base;
            T val;
            memcpy(&val, reinterpret_cast<const char *>(&mtime) + offs, sizeof(val));

            return val;
        }
        addr -= mem_base;
        if (addr + sizeof(T) > mem_size)
            throw MemFault("Out of bounds memory access");

        T val;
        memcpy(&val, reinterpret_cast<uint8_t *>(mem.get()) + addr,
               sizeof(val));
        return val;
    }

    template <typename T>
    void write_mem(uint32_t addr, T val)
    {
        if (addr >= mtime_base && addr < mtime_base + sizeof(mtime)) {
            size_t offs = addr - mtime_base;
            memcpy(reinterpret_cast<char *>(&mtime) + offs, &val, sizeof(val));

            if (offs >= sizeof(mtime.time))
                clear_timer_irq();
        }
        addr -= mem_base;
        if (addr + sizeof(T) > mem_size)
            throw MemFault("Out of bounds memory access");

        memcpy(reinterpret_cast<uint8_t *>(mem.get()) + addr, &val,
               sizeof(val));
    }

    template <typename T>
    std::vector<T> read_mem(uint32_t addr, size_t count) const
    {
        std::vector<T> data;
        for (auto m = 0; m < count; ++m, addr += sizeof(T))
            data.push_back(read_mem<T>(addr));

        return data;
    }

    void timer_tick(void)
    {
        mtime.time++;
        if (mtime.time >= mtime.cmp)
            raise_timer_irq();
    }

    std::string read_string(uint32_t addr) const;

    virtual uint32_t get_pc() const = 0;
    virtual void write_pc(uint32_t v) = 0;
    virtual void write_reg(int r, uint32_t v) = 0;
    virtual uint32_t read_reg(int r) = 0;
    virtual void step() = 0;
    virtual void raise_timer_irq() = 0;
    virtual void clear_timer_irq() = 0;

private:
    std::unique_ptr<uint32_t[]> mem;
    size_t mem_size;
    uint32_t mem_base;
    struct mtime mtime;
};
