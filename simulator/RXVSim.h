#pragma once

#include <cstring>
#include <cmath>
#include <vector>
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <functional>
#include <optional>

#include "RiscVELF.h"
#include "SimulatorBase.h"
#include "MemoryDevice.h"
#include "SimTracer.h"

struct CSRDef {
    const char *name;
    const uint32_t wr_mask;
    const uint32_t default_val;
    const uint16_t number;
};

constexpr uint32_t misa_ext_a = 1 << 0;
constexpr uint32_t misa_ext_i = 1 << 8;
constexpr uint32_t misa_ext_m = 1 << 12;
constexpr uint32_t misa_ext_s = 1 << 18;
constexpr uint32_t misa_xlen32 = 1 << 30;

constexpr uint32_t mcause_interrupt = (1U << 31);

static constexpr int sv32_levels = 2;
static constexpr int sv32_page_offset_bits = 12;
static constexpr int sv32_vpn_bits = 10;
static constexpr uint32_t sv32_page_mask = (1 << sv32_page_offset_bits) - 1;
static constexpr uint32_t sv32_megapage_mask =
    (1 << (sv32_page_offset_bits + sv32_vpn_bits)) - 1;
static constexpr uint32_t pte_valid = (1 << 0);
static constexpr uint32_t pte_read = (1 << 1);
static constexpr uint32_t pte_write = (1 << 2);
static constexpr uint32_t pte_exec = (1 << 3);
static constexpr uint32_t pte_user = (1 << 4);
static constexpr uint32_t pte_global = (1 << 5);
static constexpr uint32_t pte_accessed = (1 << 6);
static constexpr uint32_t pte_dirty = (1 << 7);

class RXVSim;

class Cache
{
public:
    Cache(size_t size, size_t num_ways, size_t line_size, MemoryBus *bus)
        : num_ways(num_ways)
        , words_per_line(line_size / sizeof(uint32_t))
        , victim(0)
        , reservation_addr(0)
        , reserved(false)
        , bus(bus)
    {
        lines_per_way = (size / num_ways) / line_size;

        ways = std::make_unique<Way[]>(num_ways);
        for (size_t way = 0; way < num_ways; ++way) {
            ways[way].lines = std::make_unique<Line[]>(lines_per_way);
            for (size_t line = 0; line < lines_per_way; ++line) {
                ways[way].lines[line].valid = ways[way].lines[line].dirty =
                    false;
                ways[way].lines[line].words =
                    std::make_unique<uint32_t[]>(line_size / sizeof(uint32_t));
            }
        }

        offset_shift = log2(sizeof(uint32_t));
        offset_bits = log2(line_size / sizeof(uint32_t));
        index_shift = offset_shift + offset_bits;
        index_bits = log2(lines_per_way);
        tag_shift = index_shift + index_bits;
        tag_bits = 30 - index_bits - log2(line_size / 4);

        assert(log2(line_size / 4) + index_bits + tag_bits == 30);
        assert(tag_bits + tag_shift == 32);
    }

    void set_noncacheable(uint32_t start, uint32_t end)
    {
        nocache_regions.emplace_back(std::make_pair(start, end));
    }

    void read(uint32_t addr, char *dst, size_t len, bool reserve = false)
    {
        if (is_noncacheable(addr)) {
            bus->read(addr, dst, len);
        } else {
            auto line = lookup(addr);
            auto addr_offset = offset(addr);
            auto byte_offset = addr & 0x3;

            assert(line != nullptr);
            memcpy(dst,
                   reinterpret_cast<const char *>(&line->words[addr_offset]) +
                       byte_offset,
                   len);

            if (reserve) {
                reserved = true;
                reservation_addr = addr & ~((1 << index_shift) - 1);
            }
        }
    }

    void write(uint32_t addr,
               const char *val,
               size_t len,
               bool conditional = false,
               bool *reservation_held = nullptr)
    {
        if (is_noncacheable(addr)) {
            bus->write(addr, val, len);
        } else {
            auto line = lookup(addr);
            auto addr_offset = offset(addr);
            auto byte_offset = addr & 0x3;

            if (conditional) {
                if (!reserved) {
                    *reservation_held = false;
                    return;
                }
                if ((addr & ~((1 << index_shift) - 1)) != reservation_addr) {
                    *reservation_held = false;
                    return;
                }
                reserved = false;
            }

            assert(line != nullptr);
            memcpy(reinterpret_cast<char *>(&line->words[addr_offset]) +
                       byte_offset,
                   val, len);
            line->dirty = true;
        }

        if (conditional)
            *reservation_held = true;
    }

    void clean()
    {
        for (size_t way = 0; way < num_ways; ++way)
            for (int idx = 0; idx < (1 << index_bits); ++idx)
                writeback(ways[way].lines[idx], idx);
    }

    void invalidate()
    {
        for (size_t way = 0; way < num_ways; ++way) {
            for (int idx = 0; idx < (1 << index_bits); ++idx) {
                ways[way].lines[idx].valid = false;
                ways[way].lines[idx].dirty = false;
            }
        }
    }

private:
    struct Line {
        uint32_t tag;
        uint32_t line_addr;
        bool valid;
        bool dirty;
        size_t num_words;
        std::unique_ptr<uint32_t[]> words;
    };

    struct Way {
        std::unique_ptr<Line[]> lines;
    };

    Line *lookup(uint32_t addr)
    {
        auto addr_index = index(addr);
        auto addr_tag = tag(addr);

        for (size_t i = 0; i < num_ways; ++i) {
            auto line = &ways[i].lines[addr_index];
            if (line->valid && line->tag == addr_tag) {
                return line;
            }
        }

        assert(victim < num_ways);
        assert(addr_index < lines_per_way);

        writeback(ways[victim].lines[addr_index], addr_index);
        fill_line(ways[victim].lines[addr_index], addr);
        auto line = &ways[victim].lines[addr_index];

        victim = (victim + 1) % num_ways;

        return line;
    }

    void writeback(Line &victim_line, int index)
    {
        if (!victim_line.valid || !victim_line.dirty)
            return;

        auto dst_addr = (victim_line.tag << tag_shift) | (index << index_shift);
        if (reserved && dst_addr == reservation_addr)
            reserved = false;
        assert(dst_addr == victim_line.line_addr);

        for (size_t i = 0; i < words_per_line;
             ++i, dst_addr += sizeof(uint32_t))
            bus->write(dst_addr,
                       reinterpret_cast<const char *>(&victim_line.words[i]),
                       sizeof(uint32_t));

        victim_line.dirty = false;
    }

    void fill_line(Line &victim_line, uint32_t addr)
    {
        assert(!victim_line.dirty);

        addr &= ~((1 << index_shift) - 1);
        victim_line.line_addr = addr;
        victim_line.tag = tag(addr);

        for (size_t i = 0; i < words_per_line; ++i, addr += sizeof(uint32_t))
            bus->read(addr, reinterpret_cast<char *>(&victim_line.words[i]),
                      sizeof(uint32_t));

        victim_line.valid = true;
        victim_line.dirty = false;
    }

    uint32_t index(uint32_t addr)
    {
        return (addr >> index_shift) & ((1 << index_bits) - 1);
    }

    uint32_t tag(uint32_t addr)
    {
        return (addr >> tag_shift) & ((1 << tag_bits) - 1);
    }

    uint32_t offset(uint32_t addr)
    {
        return (addr >> offset_shift) & ((1 << offset_bits) - 1);
    }

    bool is_noncacheable(uint32_t addr)
    {
        for (auto &r : nocache_regions) {
            if (addr >= r.first && addr < r.second)
                return true;
        }

        return false;
    }

    size_t num_ways;
    size_t lines_per_way;
    size_t words_per_line;
    std::unique_ptr<Way[]> ways;
    std::vector<std::pair<uint32_t, uint32_t>> nocache_regions;

    size_t offset_shift;
    size_t offset_bits;
    size_t index_shift;
    size_t index_bits;
    size_t tag_shift;
    size_t tag_bits;
    size_t victim;

    uint32_t reservation_addr;
    bool reserved;

    MemoryBus *bus;
};

constexpr uint32_t mstatus_sie_shift = 1;
constexpr uint32_t mstatus_mie_shift = 3;
constexpr uint32_t mstatus_spie_shift = 5;
constexpr uint32_t mstatus_mpie_shift = 7;
constexpr uint32_t mstatus_spp_shift = 8;
constexpr uint32_t mstatus_mpp_shift = 11;
constexpr uint32_t mstatus_mprv_shift = 17;
constexpr uint32_t mstatus_sum_shift = 18;
constexpr uint32_t mstatus_mxr_shift = 19;
constexpr uint32_t mstatus_tvm_shift = 20;
constexpr uint32_t mstatus_tw_shift = 21;
constexpr uint32_t mstatus_tsr_shift = 22;

struct status {
public:
    PrivilegeLevel mpp;
    PrivilegeLevel spp;
    uint32_t sie : 1;
    uint32_t mie : 1;
    uint32_t spie : 1;
    uint32_t mpie : 1;
    uint32_t mprv : 1;
    uint32_t mxr : 1;
    uint32_t tvm : 1;
    uint32_t tw : 1;
    uint32_t tsr : 1;
    uint32_t sum : 1;

    uint32_t value(PrivilegeLevel cur_level) const
    {
        uint32_t v = 0;

        if (cur_level == S || cur_level == M)
            v = (sie << mstatus_sie_shift) | (spie << mstatus_spie_shift) |
                (sum << mstatus_sum_shift) | (mxr << mstatus_mxr_shift) |
                ((static_cast<uint32_t>(spp) & 0x1) << mstatus_spp_shift);
        if (cur_level == M)
            v |= (mie << mstatus_mie_shift) | (mpie << mstatus_mpie_shift) |
                 (mprv << mstatus_mprv_shift) | (mxr << mstatus_mxr_shift) |
                 (tvm << mstatus_tvm_shift) | (tw << mstatus_tw_shift) |
                 (tsr << mstatus_tsr_shift) |
                 (static_cast<uint32_t>(mpp) << mstatus_mpp_shift);

        return v;
    }

    void set(PrivilegeLevel cur_level, uint32_t v)
    {
        if (cur_level == M) {
            mie = (v >> mstatus_mie_shift) & 0x1;
            mpie = (v >> mstatus_mpie_shift) & 0x1;
            mprv = (v >> mstatus_mprv_shift) & 0x1;
            tvm = (v >> mstatus_tvm_shift) & 0x1;
            tw = (v >> mstatus_tw_shift) & 0x1;
            tsr = (v >> mstatus_tsr_shift) & 0x1;
            auto new_mpp = static_cast<PrivilegeLevel>((v >> mstatus_mpp_shift) & 0x3);
            if (new_mpp != RESERVED)
                mpp = new_mpp;
        }

        if (cur_level == M || cur_level == S) {
            sie = (v >> mstatus_sie_shift) & 0x1;
            spp = static_cast<PrivilegeLevel>((v >> mstatus_spp_shift) & 0x1);
            spie = (v >> mstatus_spie_shift) & 0x1;
            mxr = (v >> mstatus_mxr_shift) & 0x1;
            sum = (v >> mstatus_sum_shift) & 0x1;
        }
    }
};

class RXVSim : public SimulatorBase
{
public:
    RXVSim(const std::optional<std::string> trace_name,
           size_t mem_size = default_mem_size,
           uint32_t mem_base = default_ram_base);

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
        tracer.trace_write_reg(0, r, v);
    }

    uint32_t read_reg(int r)
    {
        tracer.trace_read_reg(0, r, regs[r]);
        return regs[r];
    }

    uint32_t read_csr(int r);
    void do_write_csr(int r, uint32_t v);

    struct translation {
        uint32_t virt;
        uint32_t phys;
        uint32_t pte_addr;
        uint32_t asid;
        uint8_t attributes;
        bool valid;
    };

    bool access_valid(const translation *translation,
                      bool read,
                      bool write,
                      bool exec);

    void do_read_phys_mem(uint32_t addr, char *dst, size_t len, bool reserved)
    {
        dcache.read(addr, dst, len, reserved);
    }

    bool do_read_imem(uint32_t addr, uint32_t *phys, char *dst, size_t len)
    {
        struct translation *translation;

        if (need_translation(true)) {
            if (!translate(addr, &translation, false))
                return false;

            if (!access_valid(translation, false, false, true))
                return false;

            *phys = translation->phys;
        } else {
            *phys = addr;
        }
        icache.read(*phys, dst, len);

        tracer.trace_read_mem(0, addr, *phys, dst, len);

        return true;
    }

    bool do_write_mem(uint32_t addr,
                      uint32_t *phys,
                      const char *val,
                      size_t len,
                      bool conditional,
                      bool *reservation_held)
    {
        struct translation *translation;

        if (need_translation(false)) {
            if (!translate(addr, &translation, true))
                return false;

            if (!access_valid(translation, false, true, false))
                return false;

            *phys = translation->phys;
        } else {
            *phys = addr;
        }
        dcache.write(*phys, val, len, conditional, reservation_held);
        tracer.trace_write_mem(0, addr, *phys, val, len);

        return true;
    }

    void do_write_phys_mem(uint32_t addr,
                           const char *val,
                           size_t len,
                           bool conditional,
                           bool *reservation_held)
    {
        dcache.write(addr, val, len, conditional, reservation_held);
    }

    SimPerfStats get_perf_stats() const
    {
        SimPerfStats s;

        s.cycles = cur_cycle;
        s.retired = cur_cycle;
        s.num_irqs = num_irqs;

        return s;
    }

    void fencei()
    {
        dcache.clean();
        icache.invalidate();
    }

    void step();
    void raise_timer_irq();
    void clear_timer_irq();

    void timer_tick(void)
    {
        mtime.time++;
        if (mtime.time >= mtime.cmp)
            raise_timer_irq();
    }

    struct mtime *get_mtime()
    {
        return &this->mtime;
    }

    virtual uint64_t get_cycle() const
    {
        return cur_cycle;
    }

private:
    static const int num_tlb_entries = 4;
    struct CSR {
        const CSRDef *def;
        uint32_t val;
    };

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
        U_ECALL                 = 8,
        S_ECALL                 = 9,
        M_ECALL                 = 11,
        INSTRUCTION_PAGE_FAULT  = 12,
        LOAD_PAGE_FAULT         = 13,
        STORE_PAGE_FAULT        = 15,
    };
    // clang-format on

    bool translate(uint32_t virt, struct translation **translation, bool write);

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

    bool do_read_mem(uint32_t addr,
                     uint32_t *phys,
                     char *dst,
                     size_t len,
                     bool reserved)
    {
        struct translation *translation;

        if (need_translation(false)) {
            if (!translate(addr, &translation, false))
                return false;

            if (!access_valid(translation, true, false, false))
                return false;
            *phys = translation->phys;
        } else {
            *phys = addr;
        }

        dcache.read(*phys, dst, len, reserved);
        tracer.trace_read_mem(0, addr, *phys, dst, len);

        return true;
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
    std::optional<T> read_imem(uint32_t addr, uint32_t *phys)
    {
        std::optional<T> ret;
        T val;

        if (do_read_imem(addr, phys, reinterpret_cast<char *>(&val),
                         sizeof(val)))
            ret.emplace(val);

        return ret;
    }

    bool need_translation(bool ifetch)
    {
        if (!mmu_on || (privilege_level == M && !status.mprv) ||
            (privilege_level == M && ifetch) ||
            (status.mprv && status.mpp == M))
            return false;

        return true;
    }

    void do_exception(enum mcause_type t, uint32_t val = 0);

    static bool ad_fault(struct translation *t, bool write)
    {
        if (!(t->attributes & pte_accessed))
            return true;
        if (write && !(t->attributes & pte_dirty))
            return true;
        return false;
    }

    void check_interrupts();
    bool csr_access_allowed(int r, bool write);
    void do_xret(PrivilegeLevel level);

    std::map<uint16_t, CSR> csrs;
    uint32_t regs[32];
    uint32_t pc;
    uint32_t new_pc;
    bool exception_taken;
    struct mtime mtime;
    uint32_t ram_base;
    size_t mem_size;
    Cache dcache;
    Cache icache;
    PrivilegeLevel privilege_level;
    PrivilegeLevel new_privilege_level;
    struct status status;
    bool mmu_on;
    uint32_t translation_base;
    struct translation tlb[num_tlb_entries];
    int next_tlb_replacement;
    int last_tlb_hit;
    uint32_t asid;
    MemoryBus bus;
    SimTracer tracer;
    uint64_t cur_cycle;
    uint64_t num_irqs;
};
