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
public:
    SimTracer(const std::string &filename)
        : cur_cycle(0), insn_traced(false), filename(filename)
    {
    }

    template <typename T>
    void trace_read_mem(uint32_t addr, T val)
    {
        if (insn_traced)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, addr, val, sizeof(T), true));
    }

    template <typename T>
    void trace_write_mem(uint32_t addr, T val)
    {
        if (insn_traced)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, addr, val, sizeof(T), false));
    }

    void trace_write_reg(int r, uint32_t v)
    {
        if (insn_traced)
            cur_trace_reg_accesses.emplace_back(
                RXV::Trace::CreateRegister(trace_builder, r, false, v));
    }

    void trace_read_reg(int r, uint32_t v)
    {
        if (insn_traced)
            cur_trace_reg_accesses.emplace_back(
                RXV::Trace::CreateRegister(trace_builder, r, true, v));
    }

    void trace_start_instruction(uint32_t pc, uint32_t instr, uint64_t cycle)
    {
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
    static constexpr uint32_t default_mem_base = 0x0;
    static constexpr uint32_t mtime_base = 0xffff0000;

    SimulatorBase(const std::string trace_name,
                  size_t mem_size = default_mem_size,
                  uint32_t mem_base = default_mem_base)
        : mem_size(mem_size)
        , mem_base(mem_base)
        , cur_cycle(0)
        , tracer(trace_name)
    {
        mtime.time = mtime.cmp = 0;
        mem = std::make_unique<uint32_t[]>(mem_size / 4);
    }

    void load_elf(const RiscVELF &elf);

    template <typename T>
    T read_mem(uint32_t addr)
    {
        if (addr >= mtime_base && addr < mtime_base + sizeof(mtime)) {
            size_t offs = addr - mtime_base;
            T val;
            memcpy(&val, reinterpret_cast<const char *>(&mtime) + offs, sizeof(val));

            return val;
        }
        addr -= mem_base;
        if (addr + sizeof(T) > mem_size)
            throw MemFault("Out of bounds memory access");

        T val;
        memcpy(&val, reinterpret_cast<uint8_t *>(mem.get()) + addr,
               sizeof(val));

        tracer.trace_read_mem<T>(addr + mem_base, val);

        return val;
    }

    template <typename T>
    void write_mem(uint32_t addr, T val)
    {
        if (addr >= mtime_base && addr < mtime_base + sizeof(mtime)) {
            size_t offs = addr - mtime_base;
            memcpy(reinterpret_cast<char *>(&mtime) + offs, &val, sizeof(val));

            if (offs >= sizeof(mtime.time))
                clear_timer_irq();
        }
        addr -= mem_base;
        if (addr + sizeof(T) > mem_size)
            throw MemFault("Out of bounds memory access");

        tracer.trace_write_mem<T>(addr + mem_base, val);

        memcpy(reinterpret_cast<uint8_t *>(mem.get()) + addr, &val,
               sizeof(val));
    }

    template <typename T>
    std::vector<T> read_mem(uint32_t addr, size_t count)
    {
        std::vector<T> data;
        for (auto m = 0; m < count; ++m, addr += sizeof(T))
            data.push_back(read_mem<T>(addr));

        return data;
    }

    void timer_tick(void)
    {
        mtime.time++;
        if (mtime.time >= mtime.cmp)
            raise_timer_irq();
    }

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
    std::unique_ptr<uint32_t[]> mem;
    size_t mem_size;
    uint32_t mem_base;
    struct mtime mtime;
    uint64_t cur_cycle;

    SimTracer tracer;
};
