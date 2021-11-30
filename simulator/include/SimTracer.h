#pragma once
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <iostream>
#include <fstream>

#include "RXV.h"
#include "Trace_generated.h"

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