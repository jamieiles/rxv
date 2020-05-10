#include <iostream>
#include <vector>
#include <map>
#include <cstring>

#include "VerilogDriver.h"
#include "VRXVCore.h"
#include "SimulatorBase.h"

// clang-format off
enum CSRID {
    MVENDORID   = 0x0F11,
    MARCHID     = 0x0F12,
    MIMPID      = 0x0F13,
    MHARTID     = 0x0F14,
    MSTATUS     = 0x0300,
    MISA        = 0x0301,
    MIE         = 0x0304,
    MTVEC       = 0x0305,
    MCOUNTEREN  = 0x0306,
    MSCRATCH    = 0x0340,
    MEPC        = 0x0341,
    MCAUSE      = 0x0342,
    MTVAL       = 0x0343,
    MIP         = 0x0344,
};


enum ExCause {
    EX_INSTR_ALIGN   = 0,
    EX_INSTR_ACCESS  = 1,
    EX_ILLEGAL_INSTR = 2,
    EX_BREAKPOINT    = 3,
    EX_LOAD_ALIGN    = 4,
    EX_LOAD_ACCESS   = 5,
    EX_STORE_ALIGN   = 6,
    EX_STORE_ACCESS  = 7,
    EX_ECALL_U       = 8,
    EX_ECALL_S       = 9,
    EX_ECALL_M       = 11,
    EX_INSTR_PF      = 12,
    EX_LOAD_PF       = 13,
    EX_STORE_PF      = 15,
    EX_INTERRUPT     = 1 << 31
};
// clang-format on

class RXVCPU
    : public SimulatorBase
    , public VerilogDriver<VRXVCore>
{
public:
    RXVCPU(const std::string trace_name = std::string(default_trace_name),
           size_t mem_size = default_mem_size,
           uint32_t mem_base = default_mem_base)
        : SimulatorBase(trace_name, mem_size, mem_base),
        VerilogDriver(trace_name),
        insn_completed(false)
    {
        for (int i = 0; i < 32; ++i)
            reg_cache[i] = 0;

        reg_file_scope = svGetScopeFromName("TOP.RXVCore.RegFile");
        core_scope = svGetScopeFromName("TOP.RXVCore");
        this->dut.intr_timer = 0;
        this->dut.intr_ext = 0;

        periodic(ClockSetup, [&] {
            uint32_t v = 0;
            try {
                v = this->read_mem<uint32_t>(this->dut.i_addr);
            } catch (MemFault e) {
                v = 0;
            }
            after_n_cycles(0, [&, v] {
                this->dut.i_data = v;
            });
        });

        periodic(ClockCapture, [&] {
            if (!this->dut.rvfi_valid)
                return;

            this->insn_completed = true;
            if (this->dut.rvfi_rd_addr)
                this->reg_cache[this->dut.rvfi_rd_addr] =
                    this->dut.rvfi_rd_wdata;
            this->pc = this->dut.rvfi_pc_wdata;
        });

        periodic(ClockSetup, [&] {
            if (!this->dut.d_access)
                return;

            uint32_t mask = ((this->dut.d_bytesel & 1) ? 0x000000ff : 0) |
                            ((this->dut.d_bytesel & 2) ? 0x0000ff00 : 0) |
                            ((this->dut.d_bytesel & 4) ? 0x00ff0000 : 0) |
                            ((this->dut.d_bytesel & 8) ? 0xff000000 : 0);
            uint32_t addr = this->dut.d_addr;
            uint32_t v = this->read_mem<uint32_t>(addr) & mask;

            if (this->dut.d_wren) {
                uint32_t wdata = this->dut.d_wdata;
                after_n_cycles(0, [&, addr, wdata, mask] {
                    auto tmp = this->read_mem<uint32_t>(addr);
                    tmp &= ~mask;
                    tmp |= wdata & mask;
                    this->write_mem<uint32_t>(addr, tmp);
                });
            } else {
                after_n_cycles(0, [&, v] {
                    this->dut.d_rdata = v;
                });
            }
        });
    }

    void write_reg(int r, uint32_t v)
    {
        svSetScope(reg_file_scope);
        this->dut.write_reg(r, v);
    }

    uint32_t read_reg(int r)
    {
        assert(r < 32);
        return reg_cache[r];
    }

    void write_csr(enum CSRID csr, uint32_t v)
    {
        svSetScope(core_scope);
        this->dut.write_csr(csr, v);
    }

    uint32_t get_pc() const
    {
        return pc;
    }

    void write_pc(uint32_t v)
    {
        svSetScope(core_scope);
        pc = v;
	    this->dut.eval();
        this->dut.write_pc(v);
	    this->dut.set_reset_vector(v);
	    reset();
    }

    void step()
    {
        insn_completed = false;
        while (!insn_completed) {
            cycle();
            timer_tick();
        }
    }

    void raise_timer_irq()
    {
        after_n_cycles(1, [&] { this->dut.intr_timer = 1; });
    }

    void clear_timer_irq()
    {
        after_n_cycles(1, [&] { this->dut.intr_timer = 0; });
    }

private:
    svScope reg_file_scope;
    svScope core_scope;
    uint32_t reg_cache[32];
    uint32_t pc;
    bool insn_completed;
};
