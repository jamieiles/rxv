#pragma once

#include <cstring>
#include <vector>
#include <map>
#include <memory>
#include <string>
#include <stdexcept>

#include "RiscVELF.h"
#include "SimulatorBase.h"

struct CSRDef {
    const char *name;
    const uint32_t wr_mask;
    const uint32_t default_val;
    const uint16_t number;
};

constexpr uint32_t misa_xlen32 = 1 << 30;
constexpr uint32_t misa_ext_i = 1 << 8;

class RXVSim : public SimulatorBase
{
public:
    RXVSim(const std::string trace_name = std::string(default_trace_name),
           size_t mem_size = default_mem_size,
           uint32_t mem_base = default_mem_base);

    uint32_t get_pc() const
    {
        return pc;
    }

    void write_pc(uint32_t v)
    {
        pc = v;
    }

    void do_write_reg(int r, uint32_t v)
    {
        if (r != 0)
            regs[r] = v;
    }

    uint32_t do_read_reg(int r)
    {
        return regs[r];
    }

    void do_step();
    void raise_timer_irq()
    {
    }
    void clear_timer_irq()
    {
    }

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

    std::map<uint16_t, CSR> csrs;
    uint32_t regs[32];
    uint32_t pc;
    uint32_t new_pc;
};
