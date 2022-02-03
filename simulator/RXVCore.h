#pragma once

#include "SimTracer.h"
#include "SimulatorBase.h"
#include "MemoryDevice.h"
#include "VerilogDriver.h"
#include "UART.h"
#include "VRXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper__Syms.h"
#include "VRXVCoreEmulWrapper_RXVCoreEmulWrapper.h"
#include "VRXVCoreEmulWrapper_BusTransactor.h"

struct InstructionRecord {
    uint32_t pc;
    std::pair<int, uint32_t> reg_write;
    std::vector<std::pair<int, uint32_t>> csr_writes;
    std::vector<std::tuple<uint32_t, uint32_t, size_t>> mem_writes;
    bool excepted;
};

class ShadowTracer : public SimTracer
{
public:
    ShadowTracer(const std::optional<std::string> filename,
                 MemoryBus *shadow_bus)
        : SimTracer(filename)
        , num_instructions(0)
        , num_irqs(0)
        , last_pc(0x80000000)
        , shadow_bus(shadow_bus)
    {
        for (auto i = 0; i < 32; ++i)
            shadow_regs[i] = 0;
        for (auto i = 0; i < (1 << 12); ++i)
            shadow_csrs[i] = 0;
    }

    virtual ~ShadowTracer()
    {
    }

    virtual void trace_write_reg(int id, int r, uint32_t v) override
    {
        SimTracer::trace_write_reg(id, r, v);
        instruction_map[id].reg_write = std::make_pair(r, v);
    }

    virtual void trace_write_csr(int id, int r, uint32_t v) override
    {
        instruction_map[id].csr_writes.emplace_back(std::make_pair(r, v));

        SimTracer::trace_write_csr(id, r, v);
    }

    virtual void trace_read_reg(int id, int r, uint32_t v) override
    {
        SimTracer::trace_read_reg(id, r, v);
    }

    virtual void trace_write_mem(int id,
                                 uint32_t addr,
                                 uint32_t phys,
                                 const char *v,
                                 size_t len)
    {
        uint32_t val = 0;

        assert(len <= sizeof(val));
        memcpy(&val, v, len);
        instruction_map[id].mem_writes.emplace_back(
            std::make_tuple(phys, val, len));
        SimTracer::trace_write_mem(id, addr, phys, v, len);
    }

    virtual void trace_start_instruction(int id,
                                         uint32_t pc,
                                         uint32_t pc_phys,
                                         uint32_t instr,
                                         uint64_t cycle,
                                         PrivilegeLevel level) override
    {
        SimTracer::trace_start_instruction(id, pc, pc_phys, instr, cycle,
                                           level);
        instruction_map[id] = InstructionRecord();
        instruction_map[id].pc = pc;
    }

    virtual void trace_exception(int id) override
    {
        instruction_map[id].excepted = true;
        SimTracer::trace_exception(id);
    }

    virtual void trace_end_instruction(int id) override
    {
        SimTracer::trace_end_instruction(id);

        auto &instr = instruction_map[id];
        if (instr.reg_write.first)
            shadow_regs[instr.reg_write.first] = instr.reg_write.second;
        for (auto &csr : instr.csr_writes)
            shadow_csrs[csr.first] = csr.second;
        for (auto &mw : instr.mem_writes)
            shadow_bus->write(std::get<0>(mw),
                              reinterpret_cast<const char *>(&std::get<1>(mw)),
                              std::get<2>(mw));
        last_pc = instr.pc;

        ++num_instructions;
    }

    virtual void trace_irq(PrivilegeLevel target_level,
                           uint64_t cycle_num,
                           uint32_t cause,
                           uint32_t status,
                           uint32_t epc)
    {
        SimTracer::trace_irq(target_level, cycle_num, cause, status, epc);

        ++num_irqs;
    }

    uint32_t read_reg(int id) const
    {
        if (id < 0 || id >= 32)
            throw std::runtime_error("invalid GPR");

        return shadow_regs[id];
    }

    uint32_t read_csr(RXV::Trace::CSRId id) const
    {
        return shadow_csrs[id];
    }

    int get_num_instructions() const
    {
        return num_instructions;
    }

    uint64_t get_num_irqs() const
    {
        return num_irqs;
    }

    uint32_t get_last_pc() const
    {
        return last_pc;
    }

private:
    uint32_t shadow_regs[32];
    uint32_t shadow_csrs[4096];
    int num_instructions;
    uint64_t num_irqs;
    uint32_t last_pc;
    std::map<int, InstructionRecord> instruction_map;
    MemoryBus *shadow_bus;
};

class RTLMtime : public IOPeripheral
{
public:
    RTLMtime(uint64_t *mtime, uint64_t *mtimecmp, uint32_t base, size_t len)
        : mtime(mtime), mtimecmp(mtimecmp), IOPeripheral(base, len)
    {
    }

    void write(uint32_t offset, const char *v, size_t len)
    {
        if (offset + len > 2 * sizeof(uint64_t))
            return;

        if (offset < sizeof(uint64_t)) {
            memcpy(reinterpret_cast<char *>(mtimecmp) + offset, v, len);
        } else {
            memcpy(reinterpret_cast<char *>(mtime) + offset - sizeof(uint64_t),
                   v, len);
        }
    }

    void read(uint32_t offset, char *v, size_t len)
    {
        if (offset + len > 2 * sizeof(uint64_t)) {
            memset(v, 0, len);
            return;
        }

        if (offset < sizeof(uint64_t)) {
            memcpy(v, reinterpret_cast<char *>(mtimecmp) + offset, len);
        } else {
            memcpy(v,
                   reinterpret_cast<char *>(mtime) + offset - sizeof(uint64_t),
                   len);
        }
    }

private:
    uint64_t *mtime;
    uint64_t *mtimecmp;
};

template <bool debug_enabled = false>
class RXVCore
    : public SimulatorBase
    , public VerilogDriver<VRXVCoreEmulWrapper, debug_enabled>
{
public:
    RXVCore(const std::optional<std::string> trace_name,
            size_t mem_size = default_mem_size,
            uint32_t mem_base = default_ram_base,
            std::string instance_name = "VRXVCoreEmulWrapper")
        : VerilogDriver<VRXVCoreEmulWrapper, debug_enabled>(instance_name)
        , mem_base(mem_base)
        , shadow_bus(mem_base, mem_size, false)
        , have_reset(false)
    {
        tracer = std::make_shared<ShadowTracer>(trace_name, &shadow_bus);
        this->dut.RXVCoreEmulWrapper->RXVCore->tracer = tracer;
        bus = std::make_shared<MemoryBus>(mem_base, mem_size);
        bus->add_peripheral(std::make_unique<UART>(uart_base, 4096));
        bus->add_peripheral(std::make_unique<RTLMtime>(
            &this->dut.RXVCoreEmulWrapper->MtimeTransactor->mtime_reg,
            &this->dut.RXVCoreEmulWrapper->MtimeTransactor->mtimecmp_reg,
            mtime_base, 4096));
        this->dut.RXVCoreEmulWrapper->IBusTransactor->set_bus(bus);
        this->dut.RXVCoreEmulWrapper->DBusTransactor->set_bus(bus);
    }

    virtual ~RXVCore()
    {
    }

    void fencei()
    {
        assert(this->cur_cycle() == 0);
    }

    uint32_t get_pc() const
    {
        return tracer->get_last_pc();
    }

    void write_pc(uint32_t v)
    {
        assert(v == mem_base);
    }

    uint32_t read_reg(int r)
    {
        return tracer->read_reg(r);
    }

    uint32_t read_csr(int r)
    {
        return tracer->read_csr(static_cast<RXV::Trace::CSRId>(r));
    }

    void step()
    {
        if (!have_reset)
            do_reset();
        auto start = tracer->get_num_instructions();

        int cycles = 0;
        while (tracer->get_num_instructions() == start) {
            this->dut.RXVCoreEmulWrapper->MtimeTransactor->mtime_reg++;
            this->cycle();
        }
    }

    uint64_t get_cycle() const
    {
        return this->cur_cycle();
    }

    void do_read_phys_mem(uint32_t addr, char *dst, size_t len, bool reserved)
    {
        shadow_bus.read(addr, dst, len);
    }

    void do_write_phys_mem(uint32_t addr,
                           const char *val,
                           size_t len,
                           bool conditional,
                           bool *reservation_held)
    {
        shadow_bus.write(addr, val, len);
        bus->write(addr, val, len);
    }

    SimPerfStats get_perf_stats() const
    {
        SimPerfStats s;

        s.cycles = this->dut.RXVCoreEmulWrapper->RXVCore->RXVPMU->pmu_cycles;
        s.retired = this->dut.RXVCoreEmulWrapper->RXVCore->RXVPMU->pmu_instret;
        s.num_irqs = this->tracer->get_num_irqs();

        return s;
    }

private:
    void do_reset()
    {
        this->reset();
        have_reset = true;
    }

    uint32_t mem_base;
    MemoryBus shadow_bus;
    std::shared_ptr<MemoryBus> bus;
    std::shared_ptr<ShadowTracer> tracer;
    bool have_reset;
};
