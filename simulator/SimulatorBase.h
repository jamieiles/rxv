#pragma once
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <iostream>
#include <fstream>

#include "RiscVELF.h"
#include "MemoryDevice.h"

struct mtime {
    uint64_t cmp;
    uint64_t time;
};

struct SimPerfStats {
    uint64_t cycles;
    uint64_t retired;
    uint64_t num_irqs;
};

class SimulatorBase
{
public:
    static constexpr size_t default_mem_size = 1024 * 1024;
    static constexpr uint32_t default_ram_base = 0x0;
    static constexpr uint32_t mtime_base = 0xf0000000;
    static constexpr uint32_t uart_base = 0xffff1000;

    virtual ~SimulatorBase()
    {
    }

    void load_elf(const RiscVELF &elf);

    template <typename T>
    T read_phys_mem(uint32_t addr, bool reserved = false)
    {
        T val;

        do_read_phys_mem(addr, reinterpret_cast<char *>(&val), sizeof(val),
                         reserved);

        return val;
    }

    template <typename T>
    void write_phys_mem(uint32_t addr,
                        T val,
                        bool conditional = false,
                        bool *reservation_held = nullptr)
    {
        do_write_phys_mem(addr, reinterpret_cast<const char *>(&val),
                          sizeof(val), conditional, reservation_held);
    }

    template <typename T>
    std::vector<T> read_phys_mem_vector(uint32_t addr,
                                        size_t count,
                                        bool reserved = false)
    {
        std::vector<T> data;
        for (size_t m = 0; m < count; ++m, addr += sizeof(T))
            data.push_back(read_phys_mem<T>(addr, reserved));

        return data;
    }

    std::string read_phys_string(uint32_t addr);

    // Required simulator back-end functions
    virtual void fencei() = 0;
    virtual uint32_t get_pc() const = 0;
    virtual void write_pc(uint32_t v) = 0;
    virtual uint32_t read_reg(int r) = 0;
    virtual uint32_t read_csr(int r) = 0;
    virtual void step() = 0;
    virtual uint64_t get_cycle() const = 0;
    virtual void do_read_phys_mem(uint32_t addr,
                                  char *dst,
                                  size_t len,
                                  bool reserved) = 0;
    virtual void do_write_phys_mem(uint32_t addr,
                                   const char *val,
                                   size_t len,
                                   bool conditional,
                                   bool *reservation_held) = 0;
    virtual SimPerfStats get_perf_stats() const = 0;
};
