#include <memory>
#include <cstring>
#include "svdpi.h"
#include "MemoryDevice.h"
#include "SimTracer.h"

#include "VRXVCoreEmulWrapper__Dpi.h"

extern "C" void rxv_trace_end_instruction(void *trace_handle, int instr_id)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_end_instruction(instr_id);
}

extern "C" void rxv_trace_exception(void *trace_handle, int instr_id)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_exception(instr_id);
}

extern "C" void rxv_trace_flush(void *trace_handle)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->flush();
}

extern "C" void rxv_trace_irq(void *trace_handle,
                              int privilege,
                              const svBitVecVal *cycle,
                              const svBitVecVal *cause,
                              const svBitVecVal *status,
                              const svBitVecVal *epc)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_irq(static_cast<PrivilegeLevel>(privilege), *cycle, *cause,
                      *status, *epc);
}

extern "C" void rxv_trace_read_mem(void *trace_handle,
                                   int instr_id,
                                   const svBitVecVal *virt,
                                   const svBitVecVal *phys,
                                   const svBitVecVal *val,
                                   int size)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    switch (size) {
    case 1:
        tracer->trace_read_mem<uint8_t>(instr_id, *virt, *phys, *val);
        break;
    case 2:
        tracer->trace_read_mem<uint16_t>(instr_id, *virt, *phys, *val);
        break;
    case 4:
        tracer->trace_read_mem<uint32_t>(instr_id, *virt, *phys, *val);
        break;
    default: __builtin_unreachable();
    }
}

extern "C" void rxv_trace_read_reg(void *trace_handle,
                                   int instr_id,
                                   int regnum,
                                   const svBitVecVal *val)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_read_reg(instr_id, regnum, *val);
}

extern "C" void rxv_trace_start_instruction(void *trace_handle,
                                            int instr_id,
                                            const svBitVecVal *pc,
                                            const svBitVecVal *pc_phys,
                                            const svBitVecVal *instr,
                                            const svBitVecVal *cycle,
                                            int privilege)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_start_instruction(instr_id, *pc, *pc_phys, *instr, *cycle,
                                    static_cast<PrivilegeLevel>(privilege));
}

extern "C" void rxv_trace_write_csr(void *trace_handle,
                                    int instr_id,
                                    int csr,
                                    const svBitVecVal *val)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_write_csr(instr_id, csr, *val);
}

extern "C" void rxv_trace_write_mem(void *trace_handle,
                                    int instr_id,
                                    const svBitVecVal *virt,
                                    const svBitVecVal *phys,
                                    const svBitVecVal *val,
                                    int size)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    switch (size) {
    case 1:
        tracer->trace_write_mem<uint8_t>(instr_id, *virt, *phys, *val);
        break;
    case 2:
        tracer->trace_write_mem<uint16_t>(instr_id, *virt, *phys, *val);
        break;
    case 4:
        tracer->trace_write_mem<uint32_t>(instr_id, *virt, *phys, *val);
        break;
    default: __builtin_unreachable();
    }
}

extern "C" void rxv_trace_write_reg(void *trace_handle,
                                    int instr_id,
                                    int regnum,
                                    const svBitVecVal *val)
{
    auto tracer = static_cast<SimTracer *>(trace_handle);

    tracer->trace_write_reg(instr_id, regnum, *val);
}