// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
import RXVTypes::commit_num_entries;
import RXVTypes::commit_width;
import RXVTypes::arch_reg_tag;

package RXVTrace;

`ifdef RXV_TRACE
    logic [RXVTypes::commit_width-1:0] instr_ids[0:RXVTypes::commit_num_entries-1];

    chandle trace_handle;

    task dpi_set_trace_handle;
        input chandle handle;

        trace_handle = handle;
    endtask

    export "DPI-C" task dpi_set_trace_handle;
    import "DPI-C" function void rxv_trace_write_reg(
        input chandle        trace_handle,
        input int            instr_id,
        input int            regnum,
        input bit     [31:0] val
    );
    import "DPI-C" function void rxv_trace_read_reg(
        input chandle        trace_handle,
        input int            instr_id,
        input int            regnum,
        input bit     [31:0] val
    );
    import "DPI-C" function void rxv_trace_read_mem(
        input chandle        trace_handle,
        input int            instr_id,
        input bit     [31:0] virt,
        input bit     [31:0] phys,
        input bit     [31:0] val,
        input int            size
    );
    import "DPI-C" function void rxv_trace_write_mem(
        input chandle        trace_handle,
        input int            instr_id,
        input bit     [31:0] virt,
        input bit     [31:0] phys,
        input bit     [31:0] val,
        input int            size
    );
    import "DPI-C" function void rxv_trace_write_csr(
        input chandle        trace_handle,
        input int            instr_id,
        input int            csr,
        input bit     [31:0] val
    );
    import "DPI-C" function void rxv_trace_start_instruction(
        input chandle        trace_handle,
        input int            instr_id,
        input bit     [31:0] pc,
        input bit     [31:0] pc_phys,
        input bit     [31:0] instr,
        input bit     [63:0] cycle,
        input int            privilege
    );
    import "DPI-C" function void rxv_trace_exception(
        input chandle trace_handle,
        input int     instr_id
    );
    import "DPI-C" function void rxv_trace_end_instruction(
        input chandle trace_handle,
        input int     instr_id
    );
    import "DPI-C" function void rxv_trace_irq(
        input chandle        trace_handle,
        input int            privilege,
        input bit     [63:0] cycle,
        input bit     [31:0] cause,
        input bit     [31:0] status,
        input bit     [31:0] epc
    );
    import "DPI-C" function void rxv_trace_flush(input chandle trace_handle);
`endif

    // verilator lint_off UNUSED
    function void trace_write_reg;
        input int instr_id;
        input RXVTypes::arch_reg_tag regnum;
        input logic [31:0] val;

`ifdef RXV_TRACE
        rxv_trace_write_reg(trace_handle, integer'(instr_ids[instr_id]), integer'(regnum), val);
`endif
    endfunction


    function void trace_read_reg;
        input int instr_id;
        input RXVTypes::arch_reg_tag regnum;
        input bit [31:0] val;

`ifdef RXV_TRACE
        rxv_trace_read_reg(trace_handle, integer'(instr_ids[instr_id]), integer'(regnum), val);
`endif
    endfunction

    function void trace_read_mem;
        input int instr_id;
        input logic [31:0] virt;
        input logic [31:0] phys;
        input logic [31:0] val;
        input int size;

`ifdef RXV_TRACE
        rxv_trace_read_mem(trace_handle, integer'(instr_ids[instr_id]), virt, phys, val, size);
`endif
    endfunction

    function void trace_write_mem;
        input int instr_id;
        input logic [31:0] virt;
        input logic [31:0] phys;
        input logic [31:0] val;
        input int size;

`ifdef RXV_TRACE
        rxv_trace_write_mem(trace_handle, integer'(instr_ids[instr_id]), virt, phys, val, size);
`endif
    endfunction

    function void trace_write_csr;
        input int instr_id;
        input logic [11:0] csr;
        input logic [31:0] val;

`ifdef RXV_TRACE
        rxv_trace_write_csr(trace_handle, integer'(instr_ids[instr_id]), integer'(csr), val);
`endif
    endfunction

    function void trace_start_instruction;
        input int instr_id;
        input logic [31:2] pc;
        input logic [31:2] pc_phys;
        input logic [31:0] instr;
        input logic [1:0] privilege;

`ifdef RXV_TRACE
        instr_ids[instr_id] <= RXVTypes::commit_width'(instr_id);
        rxv_trace_start_instruction(trace_handle, integer'(instr_id), {pc, 2'b0}, {pc_phys, 2'b0},
                                    instr, $time, integer'(privilege));
`endif
    endfunction

    function void trace_uop;
        input int parent_id;
        input int uop_id;

`ifdef RXV_TRACE
        instr_ids[uop_id] <= RXVTypes::commit_width'(parent_id);
`endif
    endfunction

    function void trace_exception;
        input int instr_id;

`ifdef RXV_TRACE
        rxv_trace_exception(trace_handle, integer'(instr_ids[instr_id]));
`endif
    endfunction

    function void trace_end_instruction;
        input int instr_id;

`ifdef RXV_TRACE
        rxv_trace_end_instruction(trace_handle, integer'(instr_ids[instr_id]));
`endif
    endfunction

    function void trace_irq;
        input [1:0] privilege;
        input [31:0] cause;
        input [31:0] status;
        input [31:0] epc;

`ifdef RXV_TRACE
        rxv_trace_irq(trace_handle, integer'(privilege), $time, cause, status, epc);
`endif
    endfunction

    function void trace_flush;
`ifdef RXV_TRACE
        rxv_trace_flush(trace_handle);
`endif
    endfunction
    // verilator lint_on UNUSED

endpackage
