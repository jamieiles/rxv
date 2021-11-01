#pragma once
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <iostream>
#include <fstream>

#include "RiscVELF.h"

#include "Trace_generated.h"
#include "MemoryDevice.h"

struct mtime {
    uint64_t cmp;
    uint64_t time;
};

enum PrivilegeLevel { U = 0, S = 1, RESERVED = 2, M = 3 };

class SimTracer
{
    static constexpr bool trace_reg_reads = false;

public:
    SimTracer(const std::optional<std::string> filename)
        : enabled(false), cur_cycle(0), insn_traced(false), file_count(0)
    {
        if (filename) {
            this->enabled = true;
            this->filename_base = *filename;
        }
    }

    template <typename T>
    void trace_read_mem(uint32_t addr, uint32_t phys, T val)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, addr, phys, val, sizeof(T), true));
    }

    template <typename T>
    void trace_write_mem(uint32_t addr, uint32_t phys, T val)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, addr, phys, val, sizeof(T), false));
    }

    void trace_write_reg(int r, uint32_t v)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_reg_accesses.emplace_back(
                RXV::Trace::CreateRegister(trace_builder, r, false, v));
    }

    void trace_write_csr(int r, uint32_t v)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_csr_writes.emplace_back(RXV::Trace::CreateCSRValue(
                trace_builder, static_cast<RXV::Trace::CSRId>(r), v));
    }

    void trace_read_reg(int r, uint32_t v)
    {
        if (!enabled || !trace_reg_reads)
            return;

        if (insn_traced)
            cur_trace_reg_accesses.emplace_back(
                RXV::Trace::CreateRegister(trace_builder, r, true, v));
    }

    void trace_start_instruction(uint32_t pc,
                                 uint32_t instr,
                                 uint64_t cycle,
                                 PrivilegeLevel level)
    {
        if (!enabled)
            return;

        cur_trace_reg_accesses.clear();
        cur_trace_mem_accesses.clear();
        cur_trace_csr_writes.clear();

        trace_pc = pc;
        trace_insn = instr;
        insn_traced = true;
        cur_cycle = cycle;
        privilege_level = level;
        trace_exception_raised = false;
    }

    void trace_exception()
    {
        if (!insn_traced)
            return;

        trace_exception_raised = true;
    }

    void trace_end_instruction()
    {
        if (!insn_traced)
            return;

        auto reg_accesses = trace_builder.CreateVector(cur_trace_reg_accesses);
        auto csr_writes = trace_builder.CreateVector(cur_trace_csr_writes);
        auto mem_accesses = trace_builder.CreateVector(cur_trace_mem_accesses);
        auto insn_builder = RXV::Trace::InstructionTraceBuilder(trace_builder);

        insn_builder.add_pc(trace_pc);
        insn_builder.add_cycle_num(cur_cycle);
        insn_builder.add_exception_raised(trace_exception_raised);
        insn_builder.add_instruction(trace_insn);
        insn_builder.add_gpr_accesses(reg_accesses);
        insn_builder.add_csr_writes(csr_writes);
        insn_builder.add_mem_accesses(mem_accesses);
        insn_builder.add_privilege(
            static_cast<RXV::Trace::Privilege>(privilege_level));
        traced_insns.emplace_back(insn_builder.Finish());
        insn_traced = false;

        if (traced_insns.size() == 10000000) {
            flush();
        }
    }

    virtual ~SimTracer()
    {
        flush();
    }

    void flush()
    {
        if (!enabled)
            return;

        auto insns = trace_builder.CreateVector(traced_insns);
        auto trace = RXV::Trace::CreateProcessorTrace(trace_builder, insns);
        trace_builder.Finish(trace);

        std::ofstream insn_trace_file;
        auto filename = filename_base;
        if (file_count)
            filename += "." + std::to_string(file_count);
        insn_trace_file.open(filename, std::ios::out | std::ios::binary);
        insn_trace_file.write(
            reinterpret_cast<char *>(trace_builder.GetBufferPointer()),
            trace_builder.GetSize());
        insn_trace_file.close();

        traced_insns.clear();
        trace_builder.Reset();
        ++file_count;
    }

private:
    bool enabled;
    bool insn_traced;
    unsigned file_count;

    flatbuffers::FlatBufferBuilder trace_builder;

    std::vector<flatbuffers::Offset<RXV::Trace::Register>>
        cur_trace_reg_accesses;
    std::vector<flatbuffers::Offset<RXV::Trace::MemAccess>>
        cur_trace_mem_accesses;
    std::vector<flatbuffers::Offset<RXV::Trace::CSRValue>> cur_trace_csr_writes;
    std::vector<flatbuffers::Offset<RXV::Trace::InstructionTrace>> traced_insns;
    uint32_t trace_insn;
    uint32_t trace_pc;
    bool trace_exception_raised;
    uint64_t cur_cycle;
    std::string filename_base;
    PrivilegeLevel privilege_level;
};

class SimulatorBase
{
public:
    static constexpr size_t default_mem_size = 1024 * 1024;
    static constexpr uint32_t default_ram_base = 0x0;
    static constexpr uint32_t mtime_base = 0xf0000000;
    static constexpr uint32_t uart_base = 0xffff1000;

    SimulatorBase(const std::optional<std::string> trace_name)
        : cur_cycle(0), tracer(trace_name)
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
                        sizeof(val), reserved)) {
            ret.emplace(val);
            tracer.trace_read_mem<T>(addr, phys, val);
        }

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
                         sizeof(val))) {
            ret.emplace(val);
            tracer.trace_read_mem<T>(addr, phys, val);
        }

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

        if (ret)
            tracer.trace_write_mem<T>(addr, phys, val);

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
        tracer.trace_end_instruction();
        cur_cycle++;
    }

    void trace_instruction(uint32_t pc, uint32_t instr, PrivilegeLevel level)
    {
        tracer.trace_start_instruction(pc, instr, cur_cycle, level);
    }

    void trace_exception()
    {
        tracer.trace_exception();
    }

    std::string read_string(uint32_t addr);
    std::string read_phys_string(uint32_t addr);

    virtual uint32_t get_pc() const = 0;
    virtual void write_pc(uint32_t v) = 0;
    virtual void do_write_reg(int r, uint32_t v) = 0;
    void write_reg(int r, uint32_t v)
    {
        tracer.trace_write_reg(r, v);
        do_write_reg(r, v);
    }
    virtual uint32_t do_read_reg(int r) = 0;
    uint32_t read_reg(int r)
    {
        auto v = do_read_reg(r);
        tracer.trace_read_reg(r, v);
        return v;
    }
    void write_csr(int r, uint32_t v)
    {
        tracer.trace_write_csr(r, v);
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

    SimTracer tracer;
};
