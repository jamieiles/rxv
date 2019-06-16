#pragma once

#include <cstring>
#include <vector>
#include <map>
#include <memory>
#include <string>
#include <stdexcept>

#include "RiscVELF.h"

using MemFault = std::runtime_error;

struct CSRDef {
    const char *name;
    const uint32_t wr_mask;
    const uint32_t default_val;
    const uint16_t number;
};

constexpr uint32_t misa_xlen32 = 1 << 30;
constexpr uint32_t misa_ext_i = 1 << 8;

class RXVSim
{
public:
    static constexpr size_t default_mem_size = 1024 * 1024;
    static constexpr uint32_t default_mem_base = 0x0;

    RXVSim(size_t mem_size = default_mem_size,
           uint32_t mem_base = default_mem_base);

    void load_elf(const RiscVELF &elf);

    template <typename T>
    T read_mem(uint32_t addr) const
    {
        addr -= mem_base;
        if (addr + sizeof(T) > mem_size)
            throw MemFault("Out of bounds memory access");

        T val;
        memcpy(&val, mem.get() + addr, sizeof(val));
        return val;
    }

    template <typename T>
    void write_mem(uint32_t addr, T val)
    {
        addr -= mem_base;
        if (addr + sizeof(T) > mem_size)
            throw MemFault("Out of bounds memory access");

        memcpy(mem.get() + addr, &val, sizeof(val));
    }

    template <typename T>
    std::vector<T> read_mem(uint32_t addr, size_t count) const
    {
        std::vector<T> data;
        for (auto m = 0; m < count; ++m, addr += sizeof(T))
            data.push_back(read_mem<T>(addr));

        return data;
    }

    std::string read_string(uint32_t addr) const;

    uint32_t get_pc() const
    {
        return pc;
    }

    void write_reg(int r, uint32_t v)
    {
        if (r != 0)
            regs[r] = v;
    }

    uint32_t read_reg(int r)
    {
        return regs[r];
    }

    void step();

private:
    struct CSR {
        const CSRDef *def;
        uint32_t val;
    };

    static constexpr uint32_t mcause_interrupt = (1U << 31);
    // clang-format off
    enum mcause_type {
        M_SWINT                 = mcause_interrupt | 3,
        M_TINT                  = mcause_interrupt | 7,
        M_EINT                  = mcause_interrupt | 11,
        INSTR_ALIGN             = 0,
        ILLEGAL_INSTRUCTION     = 2,
        BREAKPOINT              = 3,
        LOAD_MISALIGN           = 4,
        STORE_MISALIGN          = 6,
        M_ECALL                 = 11
    };
    // clang-format on

    void dump_regs() const;
    void do_exception(enum mcause_type t, uint32_t val = 0);

    std::unique_ptr<uint8_t[]> mem;
    std::map<uint16_t, CSR> csrs;
    uint32_t regs[32];
    uint32_t pc;
    uint32_t new_pc;
    size_t mem_size;
    uint32_t mem_base;
};
