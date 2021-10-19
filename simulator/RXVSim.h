#pragma once

#include <cstring>
#include <cmath>
#include <vector>
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <functional>

#include "RiscVELF.h"
#include "SimulatorBase.h"

struct CSRDef {
    const char *name;
    const uint32_t wr_mask;
    const uint32_t default_val;
    const uint16_t number;
};

constexpr uint32_t misa_ext_a = 1 << 0;
constexpr uint32_t misa_ext_i = 1 << 8;
constexpr uint32_t misa_ext_m = 1 << 12;
constexpr uint32_t misa_xlen32 = 1 << 30;

class RXVSim;

class Cache
{
public:
    Cache(size_t size,
          unsigned num_ways,
          unsigned line_size,
          std::function<void(uint32_t, char *, size_t)> mem_read,
          std::function<void(uint32_t, const char *, size_t)> mem_write)
        : mem_read(mem_read)
        , mem_write(mem_write)
        , num_ways(num_ways)
        , words_per_line(line_size / sizeof(uint32_t))
        , victim(0)
        , reserved(false)
    {
        lines_per_way = (size / num_ways) / line_size;

        ways = std::make_unique<Way[]>(num_ways);
        for (auto way = 0; way < num_ways; ++way) {
            ways[way].lines = std::make_unique<Line[]>(lines_per_way);
            for (auto line = 0; line < lines_per_way; ++line) {
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
            mem_read(addr, dst, len);
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

    bool write(uint32_t addr,
               const char *val,
               size_t len,
               bool conditional = false)
    {
        if (is_noncacheable(addr)) {
            mem_write(addr, val, len);
        } else {
            auto line = lookup(addr);
            auto addr_offset = offset(addr);
            auto byte_offset = addr & 0x3;

            if (reserved && conditional) {
                if (addr & ~((1 << index_shift) - 1) != reservation_addr)
                    return false;
            }

            assert(line != nullptr);
            memcpy(reinterpret_cast<char *>(&line->words[addr_offset]) +
                       byte_offset,
                   val, len);
            line->dirty = true;
        }

        return true;
    }

    void clean()
    {
        for (int way = 0; way < num_ways; ++way)
            for (int idx = 0; idx <= (1 << index_bits); ++idx)
                writeback(ways[way].lines[idx], idx);
    }

    void invalidate()
    {
        for (int way = 0; way < num_ways; ++way) {
            for (int idx = 0; idx <= (1 << index_bits); ++idx) {
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
        size_t num_lines;
        std::unique_ptr<Line[]> lines;
    };

    Line *lookup(uint32_t addr)
    {
        auto addr_index = index(addr);
        auto addr_tag = tag(addr);

        for (int i = 0; i < num_ways; ++i) {
            auto line = &ways[i].lines[addr_index];
            if (line->valid && line->tag == addr_tag) {
                return line;
            }
        }

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
        if (dst_addr == reservation_addr)
            reserved = false;
        assert(dst_addr == victim_line.line_addr);

        for (int i = 0; i < words_per_line; ++i, dst_addr += sizeof(uint32_t))
            mem_write(dst_addr,
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

        for (int i = 0; i < words_per_line; ++i, addr += sizeof(uint32_t))
            mem_read(addr, reinterpret_cast<char *>(&victim_line.words[i]),
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

    std::function<void(uint32_t, char *, size_t)> mem_read;
    std::function<void(uint32_t, const char *, size_t)> mem_write;

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
    int victim;

    uint32_t reservation_addr;
    bool reserved;
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
    }

    uint32_t do_read_reg(int r)
    {
        return regs[r];
    }

    void do_read_mem(uint32_t addr, char *dst, size_t len, bool reserved)
    {
        dcache.read(addr, dst, len, reserved);
    }

    void do_read_imem(uint32_t addr, char *dst, size_t len)
    {
        icache.read(addr, dst, len);
    }

    bool do_write_mem(uint32_t addr,
                      const char *val,
                      size_t len,
                      bool conditional)
    {
        return dcache.write(addr, val, len, conditional);
    }

    void do_step();
    void raise_timer_irq()
    {
    }
    void clear_timer_irq()
    {
    }

    void timer_tick(void)
    {
        mtime.time++;
        if (mtime.time >= mtime.cmp)
            raise_timer_irq();
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
    void raw_read_mem(uint32_t addr, char *dst, size_t len)
    {
        if (addr >= mtime_base && addr < mtime_base + sizeof(mtime)) {
            size_t offs = addr - mtime_base;
            memcpy(dst, reinterpret_cast<const char *>(&mtime) + offs, len);
            return;
        }
        addr -= ram_base;
        if (addr + len > mem_size)
            throw MemFault("Out of bounds memory access");

        memcpy(dst, reinterpret_cast<uint8_t *>(mem.get()) + addr, len);
    }

    void raw_write_mem(uint32_t addr, const char *val, size_t len)
    {
        if (addr >= mtime_base && addr < mtime_base + sizeof(mtime)) {
            size_t offs = addr - mtime_base;
            memcpy(reinterpret_cast<char *>(&mtime) + offs, val, len);

            if (offs >= sizeof(mtime.time))
                clear_timer_irq();
        }
        addr -= ram_base;
        if (addr + len > mem_size)
            throw MemFault("Out of bounds memory access");

        memcpy(reinterpret_cast<uint8_t *>(mem.get()) + addr, val, len);
    }

    std::map<uint16_t, CSR> csrs;
    uint32_t regs[32];
    uint32_t pc;
    uint32_t new_pc;
    struct mtime mtime;
    uint32_t ram_base;
    size_t mem_size;
    std::unique_ptr<uint32_t[]> mem;
    Cache dcache;
    Cache icache;
};
