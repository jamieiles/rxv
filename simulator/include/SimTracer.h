#pragma once
#include <map>
#include <memory>
#include <string>
#include <stdexcept>
#include <iostream>
#include <fstream>

#include "RXV.h"
#include "Trace_generated.h"

struct RegisterTrace {
    int id;
    uint32_t value;
    bool read;
};

struct CSRTrace {
    int id;
    uint32_t value;
};

struct MemTrace {
    uint32_t addr;
    uint32_t phys;
    uint32_t value;
    uint8_t size;
    bool read;
};

struct InstructionTrace {
    uint64_t cycle_num;
    uint32_t pc;
    uint32_t instruction;
    std::vector<RegisterTrace> gprs;
    std::vector<MemTrace> mems;
    std::vector<CSRTrace> csrs;
    bool exception_raised;
    PrivilegeLevel privilege;
    bool traced;
};

class SimTracer
{
    static constexpr bool trace_reg_reads = false;

public:
    SimTracer(const std::optional<std::string> filename)
        : enabled(false), file_count(0)
    {
        if (filename) {
            this->enabled = true;
            this->filename_base = *filename;
        }
    }

    template <typename T>
    void trace_read_mem(int id, uint32_t addr, uint32_t phys, T val)
    {
        if (!enabled)
            return;

        if (inflight[id].traced)
            inflight[id].mems.emplace_back(MemTrace{
                addr, phys, static_cast<uint32_t>(val), sizeof(T), true});
    }

    void trace_read_mem(int id,
                        uint32_t addr,
                        uint32_t phys,
                        const char *v,
                        size_t len)
    {
        if (!enabled)
            return;

        uint32_t val = 0;
        memcpy(&val, v, len);
        if (inflight[id].traced)
            inflight[id].mems.emplace_back(
                MemTrace{addr, phys, val, static_cast<uint8_t>(len), true});
    }

    template <typename T>
    void trace_write_mem(int id, uint32_t addr, uint32_t phys, T val)
    {
        trace_write_mem(id, addr, phys, reinterpret_cast<const char *>(&val),
                        sizeof(val));
    }

    virtual void trace_write_mem(int id,
                                 uint32_t addr,
                                 uint32_t phys,
                                 const char *v,
                                 size_t len)
    {
        if (!enabled)
            return;

        uint32_t val = 0;
        memcpy(&val, v, len);
        if (inflight[id].traced)
            inflight[id].mems.emplace_back(
                MemTrace{addr, phys, val, static_cast<uint8_t>(len), false});
    }

    virtual void trace_write_reg(int id, int r, uint32_t v)
    {
        if (!enabled)
            return;

        if (inflight[id].traced)
            inflight[id].gprs.emplace_back(RegisterTrace{r, v, false});
    }

    virtual void trace_write_csr(int id, int r, uint32_t v)
    {
        if (!enabled)
            return;

        if (inflight[id].traced)
            inflight[id].csrs.emplace_back(CSRTrace{r, v});
    }

    virtual void trace_read_reg(int id, int r, uint32_t v)
    {
        if (!enabled || !trace_reg_reads)
            return;

        if (inflight[id].traced)
            inflight[id].gprs.emplace_back(RegisterTrace{r, v, true});
    }

    virtual void trace_start_instruction(int id,
                                         uint32_t pc,
                                         uint32_t instr,
                                         uint64_t cycle,
                                         PrivilegeLevel level)
    {
        if (!enabled)
            return;

        auto &instr_trace = inflight[id];
        instr_trace.cycle_num = cycle;
        instr_trace.pc = pc;
        instr_trace.instruction = instr;
        instr_trace.privilege = level;
        instr_trace.exception_raised = false;
        instr_trace.gprs.clear();
        instr_trace.mems.clear();
        instr_trace.csrs.clear();
        instr_trace.traced = true;
    }

    virtual void trace_exception(int id)
    {
        if (!inflight[id].traced)
            return;

        inflight[id].exception_raised = true;
    }

    virtual void trace_end_instruction(int id)
    {
        if (!inflight[id].traced)
            return;

        auto &instr_trace = inflight[id];
        std::vector<flatbuffers::Offset<RXV::Trace::Register>>
            cur_trace_reg_accesses;
        std::vector<flatbuffers::Offset<RXV::Trace::MemAccess>>
            cur_trace_mem_accesses;
        std::vector<flatbuffers::Offset<RXV::Trace::CSRValue>>
            cur_trace_csr_writes;
        for (auto &r : instr_trace.gprs)
            cur_trace_reg_accesses.emplace_back(RXV::Trace::CreateRegister(
                trace_builder, r.id, r.read, r.value));
        for (auto &r : instr_trace.csrs)
            cur_trace_csr_writes.emplace_back(RXV::Trace::CreateCSRValue(
                trace_builder, static_cast<RXV::Trace::CSRId>(r.id), r.value));
        for (auto &m : instr_trace.mems)
            cur_trace_mem_accesses.emplace_back(RXV::Trace::CreateMemAccess(
                trace_builder, m.addr, m.phys, m.value, m.size, m.read));

        auto reg_accesses = trace_builder.CreateVector(cur_trace_reg_accesses);
        auto csr_writes = trace_builder.CreateVector(cur_trace_csr_writes);
        auto mem_accesses = trace_builder.CreateVector(cur_trace_mem_accesses);
        auto insn_builder = RXV::Trace::InstructionTraceBuilder(trace_builder);

        insn_builder.add_pc(instr_trace.pc);
        insn_builder.add_cycle_num(instr_trace.cycle_num);
        insn_builder.add_exception_raised(instr_trace.exception_raised);
        insn_builder.add_instruction(instr_trace.instruction);
        insn_builder.add_gpr_accesses(reg_accesses);
        insn_builder.add_csr_writes(csr_writes);
        insn_builder.add_mem_accesses(mem_accesses);
        insn_builder.add_privilege(
            static_cast<RXV::Trace::Privilege>(instr_trace.privilege));
        traced_insns.emplace_back(insn_builder.Finish());

        if (traced_insns.size() == 10000000)
            flush();

        instr_trace.traced = false;
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
    unsigned file_count;
    flatbuffers::FlatBufferBuilder trace_builder;
    std::vector<flatbuffers::Offset<RXV::Trace::InstructionTrace>> traced_insns;
    std::string filename_base;
    std::map<int, InstructionTrace> inflight;
};