import RXVTypes::arch_reg_tag;

package RXVTrace;

    // verilator lint_off UNUSED
    function void trace_write_reg;
        input int instr_id;
        input RXVTypes::arch_reg_tag regnum;
        input logic [31:0] val;

`ifdef RXV_TRACE
        $c("this->tracer->trace_write_reg(", instr_id, ", ", regnum, ", ", val, ");");
`endif
    endfunction

    function void trace_read_reg;
        input int instr_id;
        input RXVTypes::arch_reg_tag regnum;
        input logic [31:0] val;

`ifdef RXV_TRACE
        $c("this->tracer->trace_read_reg(", instr_id, ", ", regnum, ", ", val, ");");
`endif
    endfunction

    function void trace_read_mem;
        input int instr_id;
        input logic [31:0] virt;
        input logic [31:0] phys;
        input logic [31:0] val;

`ifdef RXV_TRACE
        $c("this->tracer->trace_read_mem(", instr_id, ", ", virt, ", ", phys, ",", val, ");");
`endif
    endfunction

    function void trace_write_mem;
        input int instr_id;
        input logic [31:0] virt;
        input logic [31:0] phys;
        input logic [31:0] val;
        input int size;

`ifdef RXV_TRACE
        case (size)
            1:
            $c("this->tracer->trace_write_mem<uint8_t>(", instr_id, ", ", virt, ", ", phys, ",",
               val, ");");
            2:
            $c("this->tracer->trace_write_mem<uint16_t>(", instr_id, ", ", virt, ", ", phys, ",",
               val, ");");
            4:
            $c("this->tracer->trace_write_mem<uint32_t>(", instr_id, ", ", virt, ", ", phys, ",",
               val, ");");
            default: assert (1'b0);
        endcase
`endif
    endfunction

    function void trace_write_csr;
        input int instr_id;
        input logic [11:0] csr;
        input logic [31:0] val;

`ifdef RXV_TRACE
        $c("this->tracer->trace_write_csr(", instr_id, ", ", csr, ",", val, ");");
`endif
    endfunction

    function void trace_start_instruction;
        input int instr_id;
        input logic [31:2] pc;
        input logic [31:0] instr;
        input logic [1:0] privilege;

`ifdef RXV_TRACE
        $c("this->tracer->trace_start_instruction(", instr_id, ", ", {pc, 2'b0}, ",", instr, ",",
           $time, ", static_cast<PrivilegeLevel>(", privilege, "));");
`endif
    endfunction

    function void trace_exception;
        input int instr_id;

`ifdef RXV_TRACE
        $c("this->tracer->trace_exception(", instr_id, ");");
`endif
    endfunction

    function void trace_end_instruction;
        input int instr_id;

`ifdef RXV_TRACE
        $c("this->tracer->trace_end_instruction(", instr_id, ");");
`endif
    endfunction
    // verilator lint_on UNUSED

endpackage
