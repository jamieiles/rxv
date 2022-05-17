#include <cstring>
#include <iomanip>
#include <iostream>
#include <vector>
#include <map>
#include <stdexcept>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>

#include "RiscVELF.h"
#include "RXVSim.h"
#include "UART.h"

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
    TSELECT     = 0x07A0,
    TDATA1      = 0x07A1,
    TDATA2      = 0x07A2,
    TDATA3      = 0x07A3,
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
    misa_ext_s |
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
    { "mie",        0xffffffff, 0x00000000, MIE },
    { "mtvec",      0xfffffffd, 0x00000000, MTVEC },
    { "mcounteren", 0x00000000, 0x00000000, MCOUNTEREN },
    { "mscratch",   0xffffffff, 0x00000000, MSCRATCH },
    { "mepc",       0xfffffffc, 0x00000000, MEPC },
    { "mcause",     0xffffffff, 0x00000000, MCAUSE },
    { "mtval",      0xffffffff, 0x00000000, MTVAL },
    { "mip",        0xffffffff, 0x00000000, MIP },
    { "medeleg",    0xffffffff, 0x00000000, MEDELEG },
    { "mideleg",    0xffffffff, 0x00000000, MIDELEG },
    // Supervisor trap setup
    { "sstatus",    0xffffffff, 0x00000000, SSTATUS },
    { "sie",        0xffffffff, 0x00000000, SIE },
    { "stvec",      0xfffffffd, 0x00000000, STVEC },
    { "scounteren", 0x00000000, 0x00000000, SCOUNTEREN },
    { "sscratch",   0xffffffff, 0x00000000, SSCRATCH },
    { "sepc",       0xfffffffc, 0x00000000, SEPC },
    { "scause",     0xffffffff, 0x00000000, SCAUSE },
    { "stval",      0xffffffff, 0x00000000, STVAL },
    { "sip",        0xffffffff, 0x00000000, SIP },
    { "satp",       0xffffffff, 0x00000000, SATP },
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
    // Debug
    { "tselect",    0x00000000, 0x00000000, TSELECT },
    { "tdata1",     0x00000000, 0x00000000, TDATA1 },
    { "tdata2",     0x00000000, 0x00000000, TDATA2 },
    { "tdata3",     0x00000000, 0x00000000, TDATA3 },
    {}
};
// clang-format on

constexpr uint32_t mie_meie = (1 << 11);
constexpr uint32_t mie_mtie = (1 << 7);
constexpr uint32_t mie_msie = (1 << 3);
constexpr uint32_t mip_meip = (1 << 11);
constexpr uint32_t mip_mtip = (1 << 7);
constexpr uint32_t mip_msip = (1 << 3);
constexpr uint32_t mie_m_mask = mie_meie | mie_mtie | mie_msie;
constexpr uint32_t mip_m_mask = mip_meip | mip_mtip | mip_msip;

constexpr uint32_t mie_seie = (1 << 9);
constexpr uint32_t mie_stie = (1 << 5);
constexpr uint32_t mie_ssie = (1 << 1);
constexpr uint32_t mip_seip = (1 << 9);
constexpr uint32_t mip_stip = (1 << 5);
constexpr uint32_t mip_ssip = (1 << 1);
constexpr uint32_t mie_s_mask = mie_seie | mie_stie | mie_ssie;
constexpr uint32_t mip_s_mask = mip_seip | mip_stip | mip_ssip;

class CLINT : public IOPeripheral
{
public:
    CLINT(RXVSim *sim, uint32_t base, size_t len)
        : IOPeripheral(base, len), sim(sim)
    {
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        assert(len == 4);
        (void)len;

        auto mtime = sim->get_mtime();
        uint32_t v32;
        memcpy(&v32, v, sizeof(v32));

        switch (offset) {
        case 0x4000:
            mtime->cmp &= 0xffffffff00000000LU;
            mtime->cmp |= v32;
            sim->clear_timer_irq();
            break;
        case 0x4004:
            mtime->cmp &= 0x00000000ffffffffLU;
            mtime->cmp |= static_cast<uint64_t>(v32) << 32;
            sim->clear_timer_irq();
            break;
        case 0xbff8:
            mtime->time &= 0xffffffff00000000LU;
            mtime->time |= v32;
            break;
        case 0xbffc:
            mtime->time &= 0x00000000ffffffffLU;
            mtime->time |= static_cast<uint64_t>(v32) << 32;
            break;
        default: break;
        }
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        auto mtime = sim->get_mtime();

        assert(len == 4);
        (void)len;

        uint32_t v32 = 0;

        switch (offset) {
        case 0x4000: v32 = mtime->cmp; break;
        case 0x4004: v32 = mtime->cmp >> 32; break;
        case 0xbff8: v32 = mtime->time; break;
        case 0xbffc: v32 = mtime->time >> 32; break;
        default: break;
        }

        memcpy(v, &v32, sizeof(v32));
    }

private:
    RXVSim *sim;
};

RXVSim::RXVSim(const std::optional<std::string> trace_name,
               size_t mem_size,
               uint32_t mem_base)
    : pc(0)
    , new_pc(0)
    , exception_taken(false)
    , ram_base(mem_base)
    , mem_size(mem_size)
    , dcache(8192, 4, 32, &bus, false)
    , icache(8192, 4, 32, &bus, true)
    , privilege_level(M)
    , mmu_on(false)
    , translation_base(0)
    , next_tlb_replacement(0)
    , last_tlb_hit(0)
    , asid(0)
    , bus(ram_base, mem_size)
    , tracer(trace_name)
    , cur_cycle(0)
    , num_irqs(0)
{
    status.set(M, 0);
    status.mpp = M;

    for (int i = 0; i < 32; ++i)
        regs[i] = 0;

    for (auto *def = csr_defs; def->name; ++def)
        csrs[def->number] = CSR{def, def->default_val};

    mtime.time = mtime.cmp = 0;

    bus.add_peripheral(std::make_unique<CLINT>(this, mtime_base, 64 * 1024));
    dcache.set_noncacheable(mtime_base, mtime_base + 65536 - 1);
    bus.add_peripheral(std::make_unique<UART>(uart_base, 4096));
    dcache.set_noncacheable(uart_base, uart_base + 4096 - 1);
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
    auto id = static_cast<CSRID>(r);

    switch (id) {
    case SSTATUS: status.set(S, v); break;
    case MSTATUS: status.set(M, v); break;
    case SATP:
        mmu_on = !!(v & 0x80000000);
        translation_base = (v & 0x3fffff) << 12;
        asid = (v >> 22) & 0x1ff;
        csrs[SATP].val = v;
        break;
    case SIE:
        csrs[MIE].val &= ~mie_s_mask;
        csrs[MIE].val |= v & mie_s_mask;
        break;
    case SIP:
        csrs[MIP].val &= ~mip_s_mask;
        csrs[MIP].val |= v & mip_s_mask;
        break;
    default: csrs[static_cast<CSRID>(r)].val = v & wr_mask;
    }

    tracer.trace_write_csr(0, r, v);
}

uint32_t RXVSim::read_csr(int r)
{
    auto id = static_cast<CSRID>(r);

    switch (id) {
    case MCYCLE:
    case UCYCLE: return get_cycle();
    case MCYCLEH:
    case UCYCLEH: return get_cycle() >> 32;
    case UTIME: return mtime.time;
    case UTIMEH: return mtime.time >> 32;
    case SSTATUS: return status.value(S);
    case MSTATUS: return status.value(M);
    case SIP: return csrs[MIP].val & mip_s_mask;
    case SIE: return csrs[MIE].val & mie_s_mask;
    default: return csrs[id].val;
    }
}

void RXVSim::raise_timer_irq()
{
    csrs[MIP].val |= mip_mtip;
}

void RXVSim::clear_timer_irq()
{
    csrs[MIP].val &= ~mip_mtip;
}

void RXVSim::check_interrupts()
{
    if (privilege_level == M && !status.mie)
        return;

    auto active = read_csr(MIP) & read_csr(MIE);
    if (!active)
        return;

    uint32_t active_m_targets = 0;
    uint32_t active_s_targets = 0;
    auto deleg = read_csr(MIDELEG);
    for (int i = 0; i < 32; ++i) {
        if (!(active & (1 << i)))
            continue;
        if (deleg & (1 << i))
            active_s_targets |= (1 << i);
        else
            active_m_targets |= (1 << i);
    }

    if (active_m_targets) {
        auto intr = 31 - __builtin_clz(active_m_targets);
        do_exception(static_cast<mcause_type>(mcause_interrupt | intr));
        ++num_irqs;
    } else {
        auto intr = 31 - __builtin_clz(active_s_targets);
        if (privilege_level != M &&
            ((privilege_level == S && status.sie) || privilege_level == U)) {
            do_exception(static_cast<mcause_type>(mcause_interrupt | intr));
        }
        ++num_irqs;
    }
}

void RXVSim::do_xret(PrivilegeLevel level)
{
    switch (level) {
    case M:
        status.mie = status.mpie;
        status.mpie = 1;
        new_privilege_level = status.mpp;
        status.mpp = U;
        new_pc = read_csr(MEPC);
        break;
    case S:
        status.sie = status.spie;
        status.spie = 1;
        new_privilege_level = status.spp;
        status.spp = U;
        new_pc = read_csr(SEPC);
        break;
    default: throw std::runtime_error("Unreachable");
    }
}

void RXVSim::do_exception(enum mcause_type type, uint32_t val)
{
    if (exception_taken)
        return;

    CSRID xEPC;
    CSRID xCAUSE;
    CSRID xTVEC;
    CSRID xTVAL;
    auto target_level = M;
    if (type & mcause_interrupt) {
        auto interrupt_num = type & ~mcause_interrupt;
        if (read_csr(MIDELEG) & (1 << interrupt_num))
            target_level = S;
    } else if (privilege_level != M) {
        if (read_csr(MEDELEG) & (1 << type))
            target_level = S;
    }

    if (target_level < privilege_level)
        return;

    switch (target_level) {
    case M:
        xEPC = MEPC;
        xCAUSE = MCAUSE;
        xTVEC = MTVEC;
        xTVAL = MTVAL;
        status.mpie = status.mie;
        status.mie = 0;
        status.mpp = privilege_level;
        break;
    case S:
        xEPC = SEPC;
        xCAUSE = SCAUSE;
        xTVEC = STVEC;
        xTVAL = STVAL;
        status.spie = status.sie;
        status.sie = 0;
        status.spp = privilege_level;
        break;
    default: throw std::runtime_error("No user-mode traps");
    }

    do_write_csr(xEPC, pc);
    do_write_csr(xCAUSE, type);
    auto xtvec = csrs[xTVEC].val;
    new_pc = xtvec & ~0x1;

    if ((xtvec & 0x1) && (type & mcause_interrupt))
        new_pc = (xtvec & ~0x1) + (type & ~mcause_interrupt) * 4;

    switch (type) {
    case ILLEGAL_INSTRUCTION:
    case LOAD_MISALIGN:
    case STORE_MISALIGN:
    case INSTR_ALIGN:
    case INSTRUCTION_PAGE_FAULT:
    case LOAD_PAGE_FAULT:
    case STORE_PAGE_FAULT:
    case BREAKPOINT: do_write_csr(xTVAL, val); break;
    default: break;
    }

    new_privilege_level = target_level;

    if (type & mcause_interrupt)
        tracer.trace_irq(target_level, get_cycle(), type,
                         status.value(privilege_level), pc);
    tracer.trace_exception(0);
    exception_taken = true;
}

bool RXVSim::csr_access_allowed(int r, bool write)
{
    if (csrs.find(r) == csrs.end())
        return false;

    if ((((r >> 10) & 0x3) == 0x3) && write)
        return false;

    unsigned required_privilege = (r >> 8) & 0x3;
    if (static_cast<unsigned>(privilege_level) < required_privilege)
        return false;

    if (r == SATP && status.tvm)
        return false;

    return true;
}

bool RXVSim::access_valid(const translation *translation,
                          bool read,
                          bool write,
                          bool exec)
{
    if (!mmu_on)
        return true;

    auto effective_level = status.mprv ? status.mpp : privilege_level;
    if (effective_level == M && (status.mpp == M || !status.mprv))
        return true;

    if (read && !(translation->attributes & pte_read))
        return false;
    if (write && !(translation->attributes & pte_write))
        return false;
    if (exec && !(translation->attributes & pte_exec) &&
        !((translation->attributes & pte_read) && status.mxr))
        return false;
    if (effective_level == U && !(translation->attributes & pte_user))
        return false;
    if (effective_level != U && (read || write)) {
        if (!status.sum && (translation->attributes & pte_user))
            return false;
    }

    return true;
}

bool RXVSim::translate(uint32_t virt,
                       struct translation **translation,
                       bool write)
{
    for (auto i = 0, idx = last_tlb_hit; i < num_tlb_entries; ++i) {
        if (tlb[idx].valid && virt == tlb[idx].virt &&
            (tlb[idx].asid == asid || (tlb[idx].attributes & pte_global))) {
            *translation = &tlb[idx];
            last_tlb_hit = idx;
            return !ad_fault(*translation, write);
        }
        idx = (idx + 1) % num_tlb_entries;
    }

    uint32_t base = translation_base;
    uint32_t pte = 0;
    uint32_t pte_addr;
    bool megapage = false;
    for (int i = sv32_levels - 1; i >= 0; --i) {
        auto vpn = (virt >> (sv32_page_offset_bits + i * sv32_vpn_bits)) &
                   ((1 << sv32_vpn_bits) - 1);
        pte_addr = base + vpn * sizeof(uint32_t);
        dcache.read(pte_addr, reinterpret_cast<char *>(&pte), sizeof(pte),
                    false);

        if (!(pte & pte_valid))
            return false;
        if (pte & (pte_read | pte_exec)) {
            if (i > 0 && (pte & 0x000ffc00))
                return false;
            megapage = i != 0;
            break;
        }
        base = (pte << 2) & 0xfffff000;

        if (i == 0)
            return false;
    }

    *translation = &tlb[next_tlb_replacement];

    (*translation)->phys = ((pte << 2) & 0xfffff000);
    if (!megapage)
        (*translation)->phys |= (virt & sv32_page_mask);
    else
        (*translation)->phys |= (virt & sv32_megapage_mask);
    (*translation)->attributes = pte & 0xff;
    (*translation)->pte_addr = pte_addr;

    (*translation)->valid = true;
    next_tlb_replacement = (next_tlb_replacement + 1) % num_tlb_entries;

    return !ad_fault(*translation, write);
}

void RXVSim::step()
{
    exception_taken = false;

    uint32_t instr_val = 0;
    bool illegal_instruction = false;

    new_pc = pc + 4;
    new_privilege_level = privilege_level;

    uint32_t pc_phys;
    auto instr = read_imem<uint32_t>(pc, &pc_phys);
    if (instr) {
        instr_val = *instr;

        tracer.trace_start_instruction(0, pc, pc_phys, instr_val, get_cycle(),
                                       privilege_level);

        auto opcode = instr_val & 0x7f;
        auto rd = (instr_val >> 7) & 0x1f;
        auto funct3 = (instr_val >> 12) & 0x7;
        auto rs1 = (instr_val >> 15) & 0x1f;
        auto rs2 = (instr_val >> 20) & 0x1f;
        auto funct7 = (instr_val >> 25) & 0x7f;
        auto i_immed = i_immediate(instr_val);
        auto s_immed = s_immediate(instr_val);
        auto b_immed = b_immediate(instr_val);
        auto u_immed = u_immediate(instr_val);
        auto j_immed = j_immediate(instr_val);

        switch (opcode) {
        case 0x37: { // LUI
            do_write_reg(rd, u_immed);
            break;
        }
        case 0x17: { // AUIPC
            do_write_reg(rd, u_immed + pc);
            break;
        }
        case 0x6f: { // JAL
            auto next_seq_pc = pc + 4;
            new_pc = pc + sign_extend(j_immed, 21);
            if (!(new_pc & 0x3))
                do_write_reg(rd, next_seq_pc);
            break;
        }
        case 0x67: { // JALR
            new_pc = (sign_extend(i_immed, 12) + read_reg(rs1)) & ~1;
            if (!(new_pc & 0x3))
                do_write_reg(rd, pc + 4);
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
            bool abort = false;
            uint32_t v = 0;

            switch (funct3) {
            case 0x0: { // LB
                auto m = read_mem<uint8_t>(addr);
                if (m)
                    v = sign_extend(m.value(), 8);
                else
                    abort = true;
                break;
            }
            case 0x1: // LH
                if (addr & 1)
                    aligned = false;
                else {
                    auto m = read_mem<uint16_t>(addr);
                    if (m)
                        v = sign_extend(m.value(), 16);
                    else
                        abort = true;
                }
                break;
            case 0x2: // LW
                if (addr & 3)
                    aligned = false;
                else {
                    auto m = read_mem<uint32_t>(addr);
                    if (m)
                        v = m.value();
                    else
                        abort = true;
                }
                break;
            case 0x4: { // LBU
                auto m = read_mem<uint8_t>(addr);
                if (m)
                    v = m.value();
                else
                    abort = true;
                break;
            }
            case 0x5: // LHU
                if (addr & 1)
                    aligned = false;
                else {
                    auto m = read_mem<uint16_t>(addr);
                    if (m)
                        v = m.value();
                    else
                        abort = true;
                }
                break;
            default: illegal_instruction = true; break;
            }
            if (!illegal_instruction) {
                if (!aligned)
                    do_exception(LOAD_MISALIGN, addr);
                else if (abort)
                    do_exception(LOAD_PAGE_FAULT, addr);
                else
                    do_write_reg(rd, v);
            }
            break;
        }
        case 0x23: { // STORE
            auto addr = read_reg(rs1) + sign_extend(s_immed, 12);
            bool aligned = true;
            bool abort = false;

            switch (funct3) {
            case 0x0:
                if (!write_mem<uint8_t>(addr, read_reg(rs2)))
                    abort = true;
                break;
            case 0x1:
                if (addr & 1)
                    aligned = false;
                else if (!write_mem<uint16_t>(addr, read_reg(rs2)))
                    abort = true;
                break;
            case 0x2:
                if (addr & 3)
                    aligned = false;
                else if (!write_mem<uint32_t>(addr, read_reg(rs2)))
                    abort = true;
                break;
            default: illegal_instruction = true; break;
            }

            if (!illegal_instruction && !aligned)
                do_exception(STORE_MISALIGN, addr);
            else if (abort)
                do_exception(STORE_PAGE_FAULT, addr);
            break;
        }
        case 0x13: { // ARITHI
            switch (funct3) {
            case 0x0: // ADDI
                do_write_reg(rd, read_reg(rs1) + sign_extend(i_immed, 12));
                break;
            case 0x1:
                if (funct7 == 0) // SLLI
                    do_write_reg(rd, read_reg(rs1) << (i_immed & 0x1f));
                else
                    illegal_instruction = true;
                break;
            case 0x2: // SLTI
                do_write_reg(rd, static_cast<int32_t>(read_reg(rs1)) <
                                         sign_extend(i_immed, 12)
                                     ? 1
                                     : 0);
                break;
            case 0x3: // SLTIU
                do_write_reg(rd, read_reg(rs1) < static_cast<uint32_t>(
                                                     sign_extend(i_immed, 12))
                                     ? 1
                                     : 0);
                break;
            case 0x4: // XORI
                do_write_reg(rd, read_reg(rs1) ^ sign_extend(i_immed, 12));
                break;
            case 0x5:
                if (funct7 == 0) // SLRI
                    do_write_reg(rd, read_reg(rs1) >> (i_immed & 0x1f));
                else if (funct7 == 0x20) // SRAI
                    do_write_reg(rd, static_cast<int32_t>(read_reg(rs1)) >>
                                         (i_immed & 0x1f));
                else
                    illegal_instruction = true;
                break;
            case 0x6: // ORI
                do_write_reg(rd, read_reg(rs1) | sign_extend(i_immed, 12));
                break;
            case 0x7: // ANDI
                do_write_reg(rd, read_reg(rs1) & sign_extend(i_immed, 12));
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
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = *v + rs2_val;
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x1: { // AMOSWAP.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                if (!write_mem<uint32_t>(rs1_val, rs2_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x2: { // LR.W
                auto v = read_mem<uint32_t>(read_reg(rs1), true);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, read_reg(rs1));
                    break;
                }
                do_write_reg(rd, v.value());
                break;
            }
            case 0x3: { // SC.W
                bool reservation_held;
                if (!write_mem<uint32_t>(read_reg(rs1), read_reg(rs2), true,
                                         &reservation_held)) {
                    do_exception(STORE_PAGE_FAULT, read_reg(rs1));
                    break;
                }

                if (reservation_held)
                    do_write_reg(rd, 0);
                else
                    do_write_reg(rd, 1);
                break;
            }
            case 0x4: { // AMOXOR.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = *v ^ rs2_val;
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0xc: { // AMOAND.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = *v & rs2_val;
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x8: { // AMOOR.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = *v | rs2_val;
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x10: { // AMOMIN.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = std::min(static_cast<int32_t>(*v),
                                        static_cast<int32_t>(rs2_val));
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x14: { // AMOMAX.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = std::max(static_cast<int32_t>(*v),
                                        static_cast<int32_t>(rs2_val));
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x18: { // AMOMINU.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = std::min(*v, rs2_val);
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
                break;
            }
            case 0x1c: { // AMOMAXU.W
                auto rs1_val = read_reg(rs1);
                auto rs2_val = read_reg(rs2);
                auto v = read_mem<uint32_t>(rs1_val);
                if (!v) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                auto new_val = std::max(*v, rs2_val);
                if (!write_mem<uint32_t>(rs1_val, new_val)) {
                    do_exception(STORE_PAGE_FAULT, rs1_val);
                    break;
                }
                do_write_reg(rd, *v);
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
                    do_write_reg(rd, rs1_val * rs2_val);
                    break;
                }
                case 0x1: { // MULH
                    auto rs1_val = sign_extend<int64_t>(read_reg(rs1), 32);
                    auto rs2_val = sign_extend<int64_t>(read_reg(rs2), 32);
                    int64_t product = rs1_val * rs2_val;
                    do_write_reg(rd, product >> 32);
                    break;
                }
                case 0x2: { // MULHSU
                    auto rs1_val = sign_extend<int64_t>(read_reg(rs1), 32);
                    auto rs2_val = static_cast<uint64_t>(read_reg(rs2));
                    int64_t product = rs1_val * rs2_val;
                    do_write_reg(rd, product >> 32);
                    break;
                }
                case 0x3: { // MULHU
                    auto rs1_val = static_cast<uint64_t>(read_reg(rs1));
                    auto rs2_val = static_cast<uint64_t>(read_reg(rs2));
                    int64_t product = rs1_val * rs2_val;
                    do_write_reg(rd, product >> 32);
                    break;
                }
                case 0x4: { // DIV
                    auto rs1_val = read_reg(rs1);
                    auto rs2_val = read_reg(rs2);
                    if (rs2_val == 0)
                        do_write_reg(rd, 0xffffffff);
                    else if (rs1_val == 0x80000000 && rs2_val == 0xffffffff)
                        do_write_reg(rd, 0x80000000);
                    else
                        do_write_reg(rd, static_cast<int32_t>(rs1_val) /
                                             static_cast<int32_t>(rs2_val));
                    break;
                }
                case 0x5: { // DIVU
                    auto rs2_val = read_reg(rs2);
                    if (rs2_val != 0)
                        do_write_reg(rd, read_reg(rs1) / rs2_val);
                    else
                        do_write_reg(rd, 0xffffffff);
                    break;
                }
                case 0x6: { // REM
                    auto rs1_val = read_reg(rs1);
                    auto rs2_val = read_reg(rs2);
                    if (rs2_val == 0)
                        do_write_reg(rd, rs1_val);
                    else if (rs1_val == 0x80000000 && rs2_val == 0xffffffff)
                        do_write_reg(rd, 0);
                    else
                        do_write_reg(rd, static_cast<int32_t>(rs1_val) %
                                             static_cast<int32_t>(rs2_val));
                    break;
                }
                case 0x7: { // REMU
                    auto rs1_val = read_reg(rs1);
                    auto rs2_val = read_reg(rs2);
                    if (rs2_val == 0)
                        do_write_reg(rd, rs1_val);
                    else
                        do_write_reg(rd, rs1_val % rs2_val);
                    break;
                }
                }
            } else {
                switch (funct3) {
                case 0x0:
                    if (funct7 == 0) // ADD
                        do_write_reg(rd, read_reg(rs1) + read_reg(rs2));
                    else if (funct7 == 0x20) // SUB
                        do_write_reg(rd, read_reg(rs1) - read_reg(rs2));
                    else
                        illegal_instruction = true;
                    break;
                case 0x1: // SLL
                    do_write_reg(rd, read_reg(rs1) << (read_reg(rs2) & 0x1f));
                    break;
                case 0x2: // SLT
                    do_write_reg(rd, static_cast<int32_t>(read_reg(rs1)) <
                                             static_cast<int32_t>(read_reg(rs2))
                                         ? 1
                                         : 0);
                    break;
                case 0x3: // SLTU
                    do_write_reg(rd, read_reg(rs1) < read_reg(rs2) ? 1 : 0);
                    break;
                case 0x4: // XOR
                    do_write_reg(rd, read_reg(rs1) ^ read_reg(rs2));
                    break;
                case 0x5:
                    if (funct7 == 0) // SRL
                        do_write_reg(rd,
                                     read_reg(rs1) >> (read_reg(rs2) & 0x1f));
                    else if (funct7 == 0x20) // SRA
                        do_write_reg(rd, static_cast<int32_t>(read_reg(rs1)) >>
                                             (read_reg(rs2) & 0x1f));
                    else
                        illegal_instruction = true;
                    break;
                case 0x6: // OR
                    do_write_reg(rd, read_reg(rs1) | read_reg(rs2));
                    break;
                case 0x7: // AND
                    do_write_reg(rd, read_reg(rs1) & read_reg(rs2));
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
                if (instr == 0x00000073) { // ECALL
                    if (privilege_level == U)
                        do_exception(U_ECALL);
                    else if (privilege_level == S)
                        do_exception(S_ECALL);
                    else
                        do_exception(M_ECALL);
                } else if (instr == 0x00100073) { // EBREAK
                    do_exception(BREAKPOINT, pc);
                } else if (opcode == 0x73 && rs2 == 0x2 && rs1 == 0 &&
                           funct3 == 0 && rd == 0) { // xRET
                    if (funct7 == 0x8) {
                        if (privilege_level == U || status.tsr)
                            illegal_instruction = true;
                        else
                            do_xret(S);
                    } else if (funct7 == 0x18) {
                        if (privilege_level == M)
                            do_xret(M);
                        else
                            illegal_instruction = true;
                    } else
                        illegal_instruction = true;
                } else if (instr == 0x10500073) { // WFI
                    if (status.tw)
                        illegal_instruction = true;
                } else if (opcode == 0x73 && funct7 == 0x9 && funct3 == 0 &&
                           rd == 0) { // SFENCE.VMA
                    if (status.tvm)
                        illegal_instruction = true;
                    else
                        memset(tlb, 0, sizeof(tlb));
                }
                break;
            case 0x01: // CSRRW
                if (!csr_access_allowed(i_immed, true)) {
                    illegal_instruction = true;
                } else {
                    auto orig = read_reg(rs1);
                    do_write_reg(rd, read_csr(i_immed));
                    do_write_csr(i_immed, orig);
                }
                break;
            case 0x02: // CSRRS
                if (!csr_access_allowed(i_immed, rs1 != 0)) {
                    illegal_instruction = true;
                } else {
                    auto orig = read_reg(rs1);
                    do_write_reg(rd, read_csr(i_immed));
                    if (rs1 != 0)
                        do_write_csr(i_immed, read_csr(i_immed) | orig);
                }
                break;
            case 0x03: // CSRRC
                if (!csr_access_allowed(i_immed, rs1 != 0)) {
                    illegal_instruction = true;
                } else {
                    auto orig = read_reg(rs1);
                    do_write_reg(rd, read_csr(i_immed));
                    if (rs1 != 0)
                        do_write_csr(i_immed, read_csr(i_immed) & ~orig);
                }
                break;
            case 0x05: // CSRRWI
                if (!csr_access_allowed(i_immed, true)) {
                    illegal_instruction = true;
                } else {
                    if (rd != 0)
                        do_write_reg(rd, read_csr(i_immed));
                    // 5-bit zero extended immediate in the rs1 field
                    do_write_csr(i_immed, rs1);
                }
                break;
            case 0x06: // CSRRSI
                if (!csr_access_allowed(i_immed, rs1 != 0)) {
                    illegal_instruction = true;
                } else {
                    do_write_reg(rd, read_csr(i_immed));
                    // 5-bit zero extended immediate in the rs1 field
                    if (rs1 != 0)
                        do_write_csr(i_immed, read_csr(i_immed) | rs1);
                }
                break;
            case 0x07: // CSRRCI
                if (!csr_access_allowed(i_immed, rs1 != 0)) {
                    illegal_instruction = true;
                } else {
                    do_write_reg(rd, read_csr(i_immed));
                    if (rs1 != 0)
                        do_write_csr(i_immed, read_csr(i_immed) & ~rs1);
                }
                break;
            default: illegal_instruction = true; break;
            }
            break;
        default: illegal_instruction = true; break;
        }
    } else {
        tracer.trace_start_instruction(0, pc, pc, 0, get_cycle(),
                                       privilege_level);
        do_exception(INSTRUCTION_PAGE_FAULT, pc);
    }

    if (illegal_instruction)
        do_exception(ILLEGAL_INSTRUCTION, instr_val);

    if (new_pc & 0x3)
        do_exception(INSTR_ALIGN, new_pc);

    pc = new_pc;
    privilege_level = new_privilege_level;

    timer_tick();
    tracer.trace_end_instruction(0);
    check_interrupts();

    pc = new_pc;
    privilege_level = new_privilege_level;

    ++cur_cycle;
}
