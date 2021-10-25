#include <cstring>
#include <iomanip>
#include <iostream>
#include <vector>
#include <map>
#include <stdexcept>

#include "RiscVELF.h"
#include "RXVSim.h"

// clang-format off
enum CSRID {
    MVENDORID   = 0x0F11,
    MARCHID     = 0x0F12,
    MIMPID      = 0x0F13,
    MHARTID     = 0x0F14,
    UCYCLE      = 0x0C00,
    UTIME       = 0x0C01,
    UCYCLEH     = 0x0C80,
    UTIMEH      = 0x0C81,
    MCYCLE      = 0x0B00,
    MCYCLEH     = 0x0B80,
    MINSTRET    = 0x0B02,
    MINSTRETH   = 0x0B82,
    MSTATUS     = 0x0300,
    MISA        = 0x0301,
    MEDELEG     = 0x0302,
    MIDELEG     = 0x0303,
    MIE         = 0x0304,
    MTVEC       = 0x0305,
    MCOUNTEREN  = 0x0306,
    MSCRATCH    = 0x0340,
    MEPC        = 0x0341,
    MCAUSE      = 0x0342,
    MTVAL       = 0x0343,
    MIP         = 0x0344,
    SSTATUS     = 0x0100,
    SEDELEG     = 0x0102,
    SIDELEG     = 0x0103,
    SIE         = 0x0104,
    STVEC       = 0x0105,
    SCOUNTEREN  = 0x0106,
    SSCRATCH    = 0x0140,
    SEPC        = 0x0141,
    SCAUSE      = 0x0142,
    STVAL       = 0x0143,
    SIP         = 0x0144,
    SATP        = 0x0180,
};

constexpr uint32_t supported_extensions =
    misa_xlen32 |
    misa_ext_i |
    misa_ext_m |
    misa_ext_a;

static const struct CSRDef csr_defs[] = {
    // Machine information registers
    { "mvendorid",  0x00000000, 0x00000000, MVENDORID },
    { "marchid",    0x00000000, 0x00000000, MARCHID },
    { "mimpid",     0x00000000, 0x00000000, MIMPID },
    { "mhartid",    0x00000000, 0x00000000, MHARTID },
    // Machine trap setup
    { "mstatus",    0xffffffff, 3 << 11, MSTATUS },
    { "misa",       0x00000000, supported_extensions, MISA },
    { "mie",        0x00000000, 0x00000000, MIE },
    { "mtvec",      0xffffffff, 0x00000000, MTVEC },
    { "mcounteren", 0x00000000, 0x00000000, MCOUNTEREN },
    { "mscratch",   0xffffffff, 0x00000000, MSCRATCH },
    { "mepc",       0xfffffffc, 0x00000000, MEPC },
    { "mcause",     0xffffffff, 0x00000000, MCAUSE },
    { "mtval",      0xffffffff, 0x00000000, MTVAL },
    { "mip",        0x00000000, 0x00000000, MIP },
    { "medeleg",    0x00000000, 0x00000000, MEDELEG },
    { "mideleg",    0x00000000, 0x00000000, MIDELEG },
    // Supervisor trap setup
    { "sstatus",    0x00000000, 0x00000000, SSTATUS },
    { "sie",        0x00000000, 0x00000000, SIE },
    { "stvec",      0xffffffff, 0x00000000, STVEC },
    { "scounteren", 0x00000000, 0x00000000, SCOUNTEREN },
    { "sscratch",   0xffffffff, 0x00000000, SSCRATCH },
    { "sepc",       0xfffffffc, 0x00000000, SEPC },
    { "scause",     0xffffffff, 0x00000000, SCAUSE },
    { "stval",      0xffffffff, 0x00000000, STVAL },
    { "sip",        0x00000000, 0x00000000, SIP },
    { "satp",       0x00000000, 0x00000000, SATP },
    // Performance counters
    { "mcycle",     0x00000000, 0x00000000, MCYCLE },
    { "mcycleh",    0x00000000, 0x00000000, MCYCLEH },
    { "minstret",   0x00000000, 0x00000000, MINSTRET },
    { "minstreth",  0x00000000, 0x00000000, MINSTRETH },
    // Time counters
    { "ucycle",     0x00000000, 0x00000000, UCYCLE },
    { "ucycleh",    0x00000000, 0x00000000, UCYCLEH },
    { "utime",      0x00000000, 0x00000000, UTIME },
    { "utimeh",     0x00000000, 0x00000000, UTIMEH },
    {}
};
// clang-format on

class Mtime : public IOPeripheral
{
public:
    Mtime(RXVSim *sim, uint32_t base, size_t len)
        : IOPeripheral(base, len), sim(sim)
    {
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        if (offset + len > sizeof(mtime))
            return;

        auto mtime = sim->get_mtime();
        memcpy(mtime, v, len);
        sim->clear_timer_irq();
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        if (offset + len > sizeof(mtime)) {
            memset(v, 0, len);
            return;
        }

        auto mtime = sim->get_mtime();
        memcpy(v, mtime, len);
    }

private:
    RXVSim *sim;
};

class UART : public IOPeripheral
{
public:
    UART(uint32_t base, size_t len) : IOPeripheral(base, len)
    {
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        putchar(v[0]);
        fflush(stdout);
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        memset(v, 0, len);
    }
};

RXVSim::RXVSim(const std::optional<std::string> trace_name,
               size_t mem_size,
               uint32_t mem_base)
    : SimulatorBase(trace_name)
    , pc(0)
    , new_pc(0)
    , ram_base(mem_base)
    , mem_size(mem_size)
    , dcache(8192,
             4,
             32,
             std::bind(&RXVSim::raw_read_mem,
                       this,
                       std::placeholders::_1,
                       std::placeholders::_2,
                       std::placeholders::_3),
             std::bind(&RXVSim::raw_write_mem,
                       this,
                       std::placeholders::_1,
                       std::placeholders::_2,
                       std::placeholders::_3))
    , icache(8192,
             4,
             32,
             std::bind(&RXVSim::raw_read_mem,
                       this,
                       std::placeholders::_1,
                       std::placeholders::_2,
                       std::placeholders::_3),
             std::bind(&RXVSim::raw_write_mem,
                       this,
                       std::placeholders::_1,
                       std::placeholders::_2,
                       std::placeholders::_3))
    , privilege_level(M)
{
    for (int i = 0; i < 32; ++i)
        regs[i] = 0;

    for (auto *def = csr_defs; def->name; ++def)
        csrs[def->number] = CSR{def, def->default_val};

    mem = std::make_unique<uint32_t[]>(mem_size / 4);
    mtime.time = mtime.cmp = 0;

    add_peripheral(std::make_unique<Mtime>(this, mtime_base, 4096));
    add_peripheral(std::make_unique<UART>(uart_base, 4096));
}

static uint32_t i_immediate(uint32_t instr)
{
    return (instr >> 20) & 0xfff;
}

static uint32_t s_immediate(uint32_t instr)
{
    return ((instr & 0xfe000000) >> 20) | ((instr >> 7) & 0x1f);
}

static uint32_t b_immediate(uint32_t instr)
{
    return (((instr >> 7) & 0x1) << 11) | (((instr >> 8) & 0xf) << 1) |
           (((instr >> 25) & 0x3f) << 5) | (((instr >> 31) & 0x1) << 12);
}

static uint32_t u_immediate(uint32_t instr)
{
    return instr & 0xfffff000;
}

static uint32_t j_immediate(uint32_t instr)
{
    return (instr & 0xff000) | (((instr >> 20) & 0x1) << 11) |
           (((instr >> 21) & 0x3ff) << 1) | (((instr >> 31) & 0x1) << 20);
}

template <typename T = int32_t>
static T sign_extend(uint32_t u, int bits)
{
    T s = static_cast<T>(u);

    s <<= (sizeof(T) * 8) - bits;
    s >>= (sizeof(T) * 8) - bits;

    return s;
}

void RXVSim::do_write_csr(int r, uint32_t v)
{
    auto wr_mask = csrs[static_cast<CSRID>(r)].def->wr_mask;
    csrs[static_cast<CSRID>(r)].val = v & wr_mask;
}

uint32_t RXVSim::do_read_csr(int r)
{
    auto id = static_cast<CSRID>(r);
    switch (id) {
    case MCYCLE:
    case UCYCLE: return get_cycle();
    case MCYCLEH:
    case UCYCLEH: return get_cycle() >> 32;
    case UTIME: return mtime.time;
    case UTIMEH: return mtime.time >> 32;
    default: return csrs[id].val;
    }
}

void RXVSim::do_exception(enum mcause_type type, uint32_t val)
{
    write_csr(MEPC, pc);
    write_csr(MCAUSE, type);
    new_pc = csrs[MTVEC].val;

    switch (type) {
    case ILLEGAL_INSTRUCTION:
    case LOAD_MISALIGN:
    case STORE_MISALIGN:
    case INSTR_ALIGN:
    case BREAKPOINT: write_csr(MTVAL, val); break;
    default: break;
    }

    trace_exception();
}

void RXVSim::dump_regs() const
{
    for (auto i = 0; i < 32; ++i) {
        if (i % 8 == 0)
            std::cout << "x" << std::dec << i << "\t";
        std::cout << std::hex << std::setfill('0') << std::setw(8) << regs[i]
                  << " ";
        if (i % 8 == 7)
            std::cout << "\n";
    }
    std::cout.flush();
}

void RXVSim::do_step()
{
    uint32_t instr = read_imem<uint32_t>(pc);

    mtime.time++;

    trace_instruction(pc, instr, privilege_level);

    auto opcode = instr & 0x7f;
    auto rd = (instr >> 7) & 0x1f;
    auto funct3 = (instr >> 12) & 0x7;
    auto rs1 = (instr >> 15) & 0x1f;
    auto rs2 = (instr >> 20) & 0x1f;
    auto funct7 = (instr >> 25) & 0x7f;
    auto i_immed = i_immediate(instr);
    auto s_immed = s_immediate(instr);
    auto b_immed = b_immediate(instr);
    auto u_immed = u_immediate(instr);
    auto j_immed = j_immediate(instr);

    bool illegal_instruction = false;

    new_pc = pc + 4;
    switch (opcode) {
    case 0x37: { // LUI
        write_reg(rd, u_immed);
        break;
    }
    case 0x17: { // AUIPC
        write_reg(rd, u_immed + pc);
        break;
    }
    case 0x6f: { // JAL
        auto next_seq_pc = pc + 4;
        new_pc = pc + sign_extend(j_immed, 21);
        if (!(new_pc & 0x3))
            write_reg(rd, next_seq_pc);
        break;
    }
    case 0x67: { // JALR
        new_pc = (sign_extend(i_immed, 12) + read_reg(rs1)) & ~1;
        if (!(new_pc & 0x3))
            write_reg(rd, pc + 4);
        break;
    }
    case 0x63: { // BRANCH
        auto target = pc + sign_extend(b_immed, 13);
        bool taken = false;

        switch (funct3) {
        case 0x0: // BEQ
            taken = read_reg(rs1) == read_reg(rs2);
            break;
        case 0x1: // BNE
            taken = read_reg(rs1) != read_reg(rs2);
            break;
        case 0x4: // BLT
            taken = static_cast<int32_t>(read_reg(rs1)) <
                    static_cast<int32_t>(read_reg(rs2));
            break;
        case 0x5: // BGE
            taken = static_cast<int32_t>(read_reg(rs1)) >=
                    static_cast<int32_t>(read_reg(rs2));
            break;
        case 0x6: // BLTU
            taken = read_reg(rs1) < read_reg(rs2);
            break;
        case 0x7: // BGEU
            taken = read_reg(rs1) >= read_reg(rs2);
            break;
        default: illegal_instruction = true; break;
        }

        if (taken && !illegal_instruction)
            new_pc = target;
        break;
    }
    case 0x03: // LOAD
    {
        auto addr = read_reg(rs1) + sign_extend(i_immed, 12);
        bool aligned = true;
        uint32_t v = 0;

        switch (funct3) {
        case 0x0: // LB
            v = sign_extend(read_mem<uint8_t>(addr), 8);
            break;
        case 0x1: // LH
            if (addr & 1)
                aligned = false;
            else
                v = sign_extend(read_mem<uint16_t>(addr), 16);
            break;
        case 0x2: // LW
            if (addr & 3)
                aligned = false;
            else
                v = read_mem<uint32_t>(addr);
            break;
        case 0x4: // LBU
            v = read_mem<uint8_t>(addr);
            break;
        case 0x5: // LHU
            if (addr & 1)
                aligned = false;
            else
                v = read_mem<uint16_t>(addr);
            break;
        default: illegal_instruction = true; break;
        }
        if (!illegal_instruction) {
            if (!aligned)
                do_exception(LOAD_MISALIGN, addr);
            else
                write_reg(rd, v);
        }
        break;
    }
    case 0x23: { // STORE
        auto addr = read_reg(rs1) + sign_extend(s_immed, 12);
        bool aligned = true;

        switch (funct3) {
        case 0x0: write_mem<uint8_t>(addr, read_reg(rs2)); break;
        case 0x1:
            if (addr & 1)
                aligned = false;
            else
                write_mem<uint16_t>(addr, read_reg(rs2));
            break;
        case 0x2:
            if (addr & 3)
                aligned = false;
            else
                write_mem<uint32_t>(addr, read_reg(rs2));
            break;
        default: illegal_instruction = true; break;
        }

        if (!illegal_instruction && !aligned)
            do_exception(STORE_MISALIGN, addr);
        break;
    }
    case 0x13: { // ARITHI
        switch (funct3) {
        case 0x0: // ADDI
            write_reg(rd, read_reg(rs1) + sign_extend(i_immed, 12));
            break;
        case 0x1:
            if (funct7 == 0) // SLLI
                write_reg(rd, read_reg(rs1) << (i_immed & 0x1f));
            else
                illegal_instruction = true;
            break;
        case 0x2: // SLTI
            write_reg(rd, static_cast<int32_t>(read_reg(rs1)) <
                                  sign_extend(i_immed, 12)
                              ? 1
                              : 0);
            break;
        case 0x3: // SLTIU
            write_reg(rd, read_reg(rs1) < static_cast<uint32_t>(
                                              sign_extend(i_immed, 12))
                              ? 1
                              : 0);
            break;
        case 0x4: // XORI
            write_reg(rd, read_reg(rs1) ^ sign_extend(i_immed, 12));
            break;
        case 0x5:
            if (funct7 == 0) // SLRI
                write_reg(rd, read_reg(rs1) >> (i_immed & 0x1f));
            else if (funct7 == 0x20) // SRAI
                write_reg(rd, static_cast<int32_t>(read_reg(rs1)) >>
                                  (i_immed & 0x1f));
            else
                illegal_instruction = true;
            break;
        case 0x6: // ORI
            write_reg(rd, read_reg(rs1) | sign_extend(i_immed, 12));
            break;
        case 0x7: // ANDI
            write_reg(rd, read_reg(rs1) & sign_extend(i_immed, 12));
            break;
        default: break;
        }
        break;
    }
    case 0x2f: { // ATOMICS
        if (funct3 != 0x2) {
            illegal_instruction = true;
            break;
        }

        switch (funct7 >> 2) {
        case 0x0: { // AMOADD.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = v + rs2_val;
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0x1: { // AMOSWAP.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            write_mem<uint32_t>(rs1_val, rs2_val);
            break;
        }
        case 0x2: // LR.W
            write_reg(rd, read_mem<uint32_t>(read_reg(rs1), true));
            break;
        case 0x3: // SC.W
            if (write_mem<uint32_t>(read_reg(rs1), read_reg(rs2), true))
                write_reg(rd, 0);
            else
                write_reg(rd, 1);
            break;
        case 0x4: { // AMOXOR.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = v ^ rs2_val;
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0xc: { // AMOAND.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = v & rs2_val;
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0x8: { // AMOOR.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = v | rs2_val;
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0x10: { // AMOMIN.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = std::min(static_cast<int32_t>(v),
                         static_cast<int32_t>(rs2_val));
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0x14: { // AMOMAX.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = std::max(static_cast<int32_t>(v),
                         static_cast<int32_t>(rs2_val));
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0x18: { // AMOMINU.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = std::min(v, rs2_val);
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        case 0x1c: { // AMOMAXU.W
            auto rs1_val = read_reg(rs1);
            auto rs2_val = read_reg(rs2);
            auto v = read_mem<uint32_t>(rs1_val);
            write_reg(rd, v);
            v = std::max(v, rs2_val);
            write_mem<uint32_t>(rs1_val, v);
            break;
        }
        default: illegal_instruction = true; break;
        }
        break;
    }
    case 0x33: { // ARITH
        if (funct7 == 1) {
            switch (funct3) {
            case 0x0: { // MUL
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                write_reg(rd, rs1_val * rs2_val);
                break;
            }
            case 0x1: { // MULH
                auto rs1_val = sign_extend<int64_t>(read_reg(rs1), 32);
                auto rs2_val = sign_extend<int64_t>(read_reg(rs2), 32);
                int64_t product = rs1_val * rs2_val;
                write_reg(rd, product >> 32);
                break;
            }
            case 0x2: { // MULHSU
                auto rs1_val = sign_extend<int64_t>(read_reg(rs1), 32);
                auto rs2_val = static_cast<uint64_t>(read_reg(rs2));
                int64_t product = rs1_val * rs2_val;
                write_reg(rd, product >> 32);
                break;
            }
            case 0x3: { // MULHU
                auto rs1_val = static_cast<uint64_t>(read_reg(rs1));
                auto rs2_val = static_cast<uint64_t>(read_reg(rs2));
                int64_t product = rs1_val * rs2_val;
                write_reg(rd, product >> 32);
                break;
            }
            case 0x4: { // DIV
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                if (rs2_val == 0)
                    write_reg(rd, 0xffffffff);
                else if (rs1_val == 0x80000000 && rs2_val == 0xffffffff)
                    write_reg(rd, 0x80000000);
                else
                    write_reg(rd, static_cast<int32_t>(rs1_val) /
                                      static_cast<int32_t>(rs2_val));
                break;
            }
            case 0x5: { // DIVU
                auto rs2_val = read_reg(rs2);
                if (rs2_val != 0)
                    write_reg(rd, read_reg(rs1) / rs2_val);
                else
                    write_reg(rd, 0xffffffff);
                break;
            }
            case 0x6: { // REM
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                if (rs2_val == 0)
                    write_reg(rd, rs1_val);
                else if (rs1_val == 0x80000000 && rs2_val == 0xffffffff)
                    write_reg(rd, 0);
                else
                    write_reg(rd, static_cast<int32_t>(rs1_val) %
                                      static_cast<int32_t>(rs2_val));
                break;
            }
            case 0x7: { // REMU
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                if (rs2_val == 0)
                    write_reg(rd, rs1_val);
                else
                    write_reg(rd, rs1_val % rs2_val);
                break;
            }
            }
        } else {
            switch (funct3) {
            case 0x0:
                if (funct7 == 0) // ADD
                    write_reg(rd, read_reg(rs1) + read_reg(rs2));
                else if (funct7 == 0x20) // SUB
                    write_reg(rd, read_reg(rs1) - read_reg(rs2));
                else
                    illegal_instruction = true;
                break;
            case 0x1: // SLL
                write_reg(rd, read_reg(rs1) << (read_reg(rs2) & 0x1f));
                break;
            case 0x2: // SLT
                write_reg(rd, static_cast<int32_t>(read_reg(rs1)) <
                                      static_cast<int32_t>(read_reg(rs2))
                                  ? 1
                                  : 0);
                break;
            case 0x3: // SLTU
                write_reg(rd, read_reg(rs1) < read_reg(rs2) ? 1 : 0);
                break;
            case 0x4: // XOR
                write_reg(rd, read_reg(rs1) ^ read_reg(rs2));
                break;
            case 0x5:
                if (funct7 == 0) // SRL
                    write_reg(rd, read_reg(rs1) >> (read_reg(rs2) & 0x1f));
                else if (funct7 == 0x20) // SRA
                    write_reg(rd, static_cast<int32_t>(read_reg(rs1)) >>
                                      (read_reg(rs2) & 0x1f));
                else
                    illegal_instruction = true;
                break;
            case 0x6: // OR
                write_reg(rd, read_reg(rs1) | read_reg(rs2));
                break;
            case 0x7: // AND
                write_reg(rd, read_reg(rs1) & read_reg(rs2));
                break;
            }
        }
        break;
    }
    case 0x0f:
        if (funct3 == 0x1) {
            dcache.clean();
            icache.invalidate();
        }
        break; // FENCE
    case 0x73:
        switch (funct3) {
        case 0x00:
            if (instr == 0x00000073) // ECALL
                do_exception(M_ECALL);
            else if (instr == 0x00100073) // EBREAK
                do_exception(BREAKPOINT, pc);
            else if (instr == 0x30200073) // MRET
                new_pc = read_csr(MEPC);
            else if (instr == 0x10500073) // WFI
                ;
            else
                illegal_instruction = true;
            break;
        case 0x01: // CSRRW
            if (csrs.find(i_immed) == csrs.end()) {
                illegal_instruction = true;
            } else {
                auto orig = read_reg(rs1);
                write_reg(rd, read_csr(i_immed));
                write_csr(i_immed, orig);
            }
            break;
        case 0x02: // CSRRS
            if (csrs.find(i_immed) == csrs.end()) {
                illegal_instruction = true;
            } else {
                auto orig = read_reg(rs1);
                write_reg(rd, read_csr(i_immed));
                if (rs1 != 0)
                    write_csr(i_immed, read_csr(i_immed) | orig);
            }
            break;
        case 0x03: // CSRRC
            if (csrs.find(i_immed) == csrs.end()) {
                illegal_instruction = true;
            } else {
                auto orig = read_reg(rs1);
                write_reg(rd, read_csr(i_immed));
                if (rs1 != 0)
                    write_csr(i_immed, read_csr(i_immed) & ~orig);
            }
            break;
        case 0x05: // CSRRWI
            if (csrs.find(i_immed) == csrs.end()) {
                illegal_instruction = true;
            } else {
                if (rd != 0)
                    write_reg(rd, read_csr(i_immed));
                // 5-bit zero extended immediate in the rs1 field
                write_csr(i_immed, rs1);
            }
            break;
        case 0x06: // CSRRSI
            if (csrs.find(i_immed) == csrs.end()) {
                illegal_instruction = true;
            } else {
                write_reg(rd, read_csr(i_immed));
                // 5-bit zero extended immediate in the rs1 field
                if (rs1 != 0)
                    write_csr(i_immed, read_csr(i_immed) | rs1);
            }
            break;
        case 0x07: // CSRRCI
            if (csrs.find(i_immed) == csrs.end()) {
                illegal_instruction = true;
            } else {
                write_reg(rd, read_csr(i_immed));
                if (rs1 != 0)
                    write_csr(i_immed, read_csr(i_immed) & ~rs1);
            }
            break;
        default: illegal_instruction = true; break;
        }
        break;
    default: illegal_instruction = true; break;
    }

    if (illegal_instruction)
        do_exception(ILLEGAL_INSTRUCTION, instr);

    if (new_pc & 0x3)
        do_exception(INSTR_ALIGN, new_pc);

    pc = new_pc;

    timer_tick();
}
