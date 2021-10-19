#pragma once
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <iostream>
#include <fstream>

#include "RiscVELF.h"

#include "Trace_generated.h"

using MemFault = std::runtime_error;

struct mtime {
    uint64_t time;
    uint64_t cmp;
};

class SimTracer
{
    static constexpr bool trace_reg_reads = false;

public:
    SimTracer(const std::optional<std::string> filename)
        : enabled(false), cur_cycle(0), insn_traced(false)
    {
        if (filename) {
            this->enabled = true;
            this->filename = *filename;
        }
    }

    template <typename T>
    void trace_read_mem(uint32_t addr, T val)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, addr, val, sizeof(T), true));
    }

    template <typename T>
    void trace_write_mem(uint32_t addr, T val)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, addr, val, sizeof(T), false));
    }

    void trace_write_reg(int r, uint32_t v)
    {
        if (!enabled)
            return;

        if (insn_traced)
            cur_trace_reg_accesses.emplace_back(
                RXV::Trace::CreateRegister(trace_builder, r, false, v));
    }

    void trace_read_reg(int r, uint32_t v)
    {
        if (!enabled || !trace_reg_reads)
            return;

        if (insn_traced)
            cur_trace_reg_accesses.emplace_back(
                RXV::Trace::CreateRegister(trace_builder, r, true, v));
    }

    void trace_start_instruction(uint32_t pc, uint32_t instr, uint64_t cycle)
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
    }

    void trace_end_instruction()
    {
        if (!insn_traced)
            return;
        auto reg_accesses = trace_builder.CreateVector(cur_trace_reg_accesses);
        auto mem_accesses = trace_builder.CreateVector(cur_trace_mem_accesses);
        auto insn_builder = RXV::Trace::InstructionTraceBuilder(trace_builder);

        insn_builder.add_pc(trace_pc);
        insn_builder.add_cycle_num(cur_cycle);
        insn_builder.add_instruction(trace_insn);
        insn_builder.add_gpr_accesses(reg_accesses);
        insn_builder.add_mem_accesses(mem_accesses);
        traced_insns.emplace_back(insn_builder.Finish());
        insn_traced = false;
    }

    virtual ~SimTracer()
    {
        if (!enabled)
            return;
        auto insns = trace_builder.CreateVector(traced_insns);
        auto trace = RXV::Trace::CreateProcessorTrace(trace_builder, insns);
        trace_builder.Finish(trace);

        std::ofstream insn_trace_file;
        insn_trace_file.open(filename, std::ios::out | std::ios::binary);
        insn_trace_file.write(
            reinterpret_cast<char *>(trace_builder.GetBufferPointer()),
            trace_builder.GetSize());
        insn_trace_file.close();
    }

private:
    bool enabled;
    bool insn_traced;

    flatbuffers::FlatBufferBuilder trace_builder;

    std::vector<flatbuffers::Offset<RXV::Trace::Register>>
        cur_trace_reg_accesses;
    std::vector<flatbuffers::Offset<RXV::Trace::MemAccess>>
        cur_trace_mem_accesses;
    std::vector<flatbuffers::Offset<RXV::Trace::CSRValue>> cur_trace_csr_writes;
    std::vector<flatbuffers::Offset<RXV::Trace::InstructionTrace>> traced_insns;
    uint32_t trace_insn;
    uint32_t trace_pc;
    uint64_t cur_cycle;
    std::string filename;
};

class SimulatorBase
{
public:
    static constexpr char default_trace_name[] = "RXVCore.vcd";
    static constexpr size_t default_mem_size = 1024 * 1024;
    static constexpr uint32_t default_ram_base = 0x0;
    static constexpr uint32_t mtime_base = 0xffff0000;

    SimulatorBase(const std::optional<std::string> trace_name)
        : cur_cycle(0), tracer(trace_name)
    {
    }

    void load_elf(const RiscVELF &elf);

    virtual void do_read_mem(uint32_t addr,
                             char *dst,
                             size_t len,
                             bool reserved) = 0;
    virtual void do_read_imem(uint32_t addr, char *dst, size_t len) = 0;

    virtual bool do_write_mem(uint32_t addr,
                              const char *val,
                              size_t len,
                              bool conditional) = 0;

    template <typename T>
    T read_mem(uint32_t addr, bool reserved = false)
    {
        T val;

        do_read_mem(addr, reinterpret_cast<char *>(&val), sizeof(val),
                    reserved);

        tracer.trace_read_mem<T>(addr, val);

        return val;
    }

    template <typename T>
    T read_imem(uint32_t addr)
    {
        T val;

        do_read_mem(addr, reinterpret_cast<char *>(&val), sizeof(val), false);

        tracer.trace_read_mem<T>(addr, val);

        return val;
    }

    template <typename T>
    bool write_mem(uint32_t addr, T val, bool conditional = false)
    {
        auto ret = do_write_mem(addr, reinterpret_cast<const char *>(&val),
                                sizeof(val), conditional);

        if (ret)
            tracer.trace_write_mem<T>(addr, val);

        return ret;
    }

    template <typename T>
    std::vector<T> read_mem_vector(uint32_t addr,
                                   size_t count,
                                   bool reserved = false)
    {
        std::vector<T> data;
        for (auto m = 0; m < count; ++m, addr += sizeof(T))
            data.push_back(read_mem<T>(addr, reserved));

        return data;
    }

    virtual void timer_tick(void) = 0;

    void step()
    {
        do_step();
        tracer.trace_end_instruction();
        cur_cycle++;
    }

    void trace_instruction(uint32_t pc, uint32_t instr)
    {
        tracer.trace_start_instruction(pc, instr, cur_cycle);
    }

    std::string read_string(uint32_t addr);

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
    virtual void do_step() = 0;
    virtual void raise_timer_irq() = 0;
    virtual void clear_timer_irq() = 0;

private:
    uint64_t cur_cycle;

    SimTracer tracer;
};
