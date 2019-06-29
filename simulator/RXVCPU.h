#include <iostream>
#include <vector>
#include <map>
#include <cstring>

#include "VerilogTestbench.h"
#include "VRXVCore.h"

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
    EX_STORE_PF      = 15
};
// clang-format on

class RXVCPU : public VerilogTestbench<VRXVCore>
{
public:
    static constexpr int num_instructions = 512 * 1024 * 4;

    RXVCPU()
    {
        reg_file_scope = svGetScopeFromName("TOP.RXVCore.RegFile");
        csr_scope = svGetScopeFromName("TOP.RXVCore");

        periodic(ClockSetup, [&] {
            after_n_cycles(0, [&] {
                if ((this->dut.i_addr >> 2) >= num_instructions)
                    instr_fetch_oob(this->dut.i_addr);
                this->dut.i_data = this->mem[this->dut.i_addr >> 2];
            });
        });

        periodic(ClockSetup, [&] {
            if (!this->dut.d_access)
                return;
            if (this->dut.d_addr & 0x3)
                throw std::runtime_error("error: unaligned data access");

            uint32_t mask = ((this->dut.d_bytesel & 1) ? 0x000000ff : 0) |
                            ((this->dut.d_bytesel & 2) ? 0x0000ff00 : 0) |
                            ((this->dut.d_bytesel & 4) ? 0x00ff0000 : 0) |
                            ((this->dut.d_bytesel & 8) ? 0xff000000 : 0);
            uint32_t addr = this->dut.d_addr;

            if ((addr >> 2) >= num_instructions)
                data_access_oob(this->dut.d_addr);
            if (this->dut.d_wren) {
                uint32_t wdata = this->dut.d_wdata;
                after_n_cycles(0, [&, addr, wdata, mask] {
                    this->mem[addr >> 2] &= ~mask;
                    this->mem[addr >> 2] |= wdata & mask;
                });
            } else {
                after_n_cycles(0, [&, addr, mask] {
                    this->dut.d_rdata = this->mem[addr >> 2] & mask;
                });
            }
        });
    }

    virtual void instr_fetch_oob(uint32_t addr)
    {
    }

    virtual void data_access_oob(uint32_t addr)
    {
    }

    void write_reg(int r, int v)
    {
        svSetScope(reg_file_scope);
        this->dut.write_reg(r, v);
    }

    void write_csr(enum CSRID csr, uint32_t v)
    {
        svSetScope(csr_scope);
        this->dut.write_csr(csr, v);
    }

    uint32_t mem[num_instructions];

private:
    svScope reg_file_scope;
    svScope csr_scope;
};
