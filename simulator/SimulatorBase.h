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

class SimulatorBase
{
public:
    static constexpr size_t default_mem_size = 1024 * 1024;
    static constexpr uint32_t default_ram_base = 0x0;
    static constexpr uint32_t mtime_base = 0xf0000000;
    static constexpr uint32_t uart_base = 0xffff1000;

    SimulatorBase(const std::optional<std::string> trace_name) : cur_cycle(0)
    {
    }

    void load_elf(const RiscVELF &elf);

    virtual bool do_read_mem(uint32_t addr,
                             uint32_t *phys,
                             char *dst,
                             size_t len,
                             bool reserved) = 0;
    virtual void do_read_phys_mem(uint32_t addr,
                                  char *dst,
                                  size_t len,
                                  bool reserved) = 0;
    virtual bool do_read_imem(uint32_t addr,
                              uint32_t *phys,
                              char *dst,
                              size_t len) = 0;

    virtual bool do_write_mem(uint32_t addr,
                              uint32_t *phys,
                              const char *val,
                              size_t len,
                              bool conditional,
                              bool *reservation_held) = 0;
    virtual void do_write_phys_mem(uint32_t addr,
                                   const char *val,
                                   size_t len,
                                   bool conditional,
                                   bool *reservation_held) = 0;

    template <typename T>
    std::optional<T> read_mem(uint32_t addr, bool reserved = false)
    {
        std::optional<T> ret;
        T val;
        uint32_t phys;

        if (do_read_mem(addr, &phys, reinterpret_cast<char *>(&val),
                        sizeof(val), reserved))
            ret.emplace(val);

        return ret;
    }

    template <typename T>
    T read_phys_mem(uint32_t addr, bool reserved = false)
    {
        T val;

        do_read_phys_mem(addr, reinterpret_cast<char *>(&val), sizeof(val),
                         reserved);

        return val;
    }

    template <typename T>
    std::optional<T> read_imem(uint32_t addr)
    {
        std::optional<T> ret;
        T val;
        uint32_t phys;

        if (do_read_imem(addr, &phys, reinterpret_cast<char *>(&val),
                         sizeof(val)))
            ret.emplace(val);

        return ret;
    }

    template <typename T>
    bool write_mem(uint32_t addr,
                   T val,
                   bool conditional = false,
                   bool *reservation_held = nullptr)
    {
        uint32_t phys;

        auto ret =
            do_write_mem(addr, &phys, reinterpret_cast<const char *>(&val),
                         sizeof(val), conditional, reservation_held);

        return ret;
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
        for (auto m = 0; m < count; ++m, addr += sizeof(T))
            data.push_back(read_phys_mem<T>(addr, reserved));

        return data;
    }

    virtual void fencei() = 0;

    virtual void timer_tick(void) = 0;

    void step()
    {
        do_step();
        cur_cycle++;
    }

    std::string read_string(uint32_t addr);
    std::string read_phys_string(uint32_t addr);

    virtual uint32_t get_pc() const = 0;
    virtual void write_pc(uint32_t v) = 0;
    virtual void do_write_reg(int r, uint32_t v) = 0;
    void write_reg(int r, uint32_t v)
    {
        do_write_reg(r, v);
    }
    virtual uint32_t do_read_reg(int r) = 0;
    uint32_t read_reg(int r)
    {
        auto v = do_read_reg(r);
        return v;
    }
    void write_csr(int r, uint32_t v)
    {
        do_write_csr(r, v);
    }
    virtual void do_write_csr(int r, uint32_t v) = 0;

    uint32_t read_csr(int r)
    {
        return do_read_csr(r);
    }
    virtual uint32_t do_read_csr(int r) = 0;

    virtual void do_step() = 0;
    virtual void raise_timer_irq() = 0;
    virtual void clear_timer_irq() = 0;

    uint64_t get_cycle() const
    {
        return cur_cycle;
    }

private:
    uint64_t cur_cycle;
};
