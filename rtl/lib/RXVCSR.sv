package RXVCSR;

    typedef enum logic [11:0] {
        CSR_MVENDORID  = 12'hF11,
        CSR_MARCHID    = 12'hF12,
        CSR_MIMPID     = 12'hF13,
        CSR_MHARTID    = 12'hF14,
        CSR_UCYCLE     = 12'hC00,
        CSR_UTIME      = 12'hC01,
        CSR_UCYCLEH    = 12'hC80,
        CSR_UTIMEH     = 12'hC81,
        CSR_MCYCLE     = 12'hB00,
        CSR_MCYCLEH    = 12'hB80,
        CSR_MINSTRET   = 12'hB02,
        CSR_MINSTRETH  = 12'hB82,
        CSR_TSELECT    = 12'h7A0,
        CSR_TDATA1     = 12'h7A1,
        CSR_TDATA2     = 12'h7A2,
        CSR_TDATA3     = 12'h7A3,
        CSR_MSTATUS    = 12'h300,
        CSR_MISA       = 12'h301,
        CSR_MEDELEG    = 12'h302,
        CSR_MIDELEG    = 12'h303,
        CSR_MIE        = 12'h304,
        CSR_MTVEC      = 12'h305,
        CSR_MCOUNTEREN = 12'h306,
        CSR_MSCRATCH   = 12'h340,
        CSR_MEPC       = 12'h341,
        CSR_MCAUSE     = 12'h342,
        CSR_MTVAL      = 12'h343,
        CSR_MIP        = 12'h344,
        CSR_SSTATUS    = 12'h100,
        CSR_SEDELEG    = 12'h102,
        CSR_SIDELEG    = 12'h103,
        CSR_SIE        = 12'h104,
        CSR_STVEC      = 12'h105,
        CSR_SCOUNTEREN = 12'h106,
        CSR_SSCRATCH   = 12'h140,
        CSR_SEPC       = 12'h141,
        CSR_SCAUSE     = 12'h142,
        CSR_STVAL      = 12'h143,
        CSR_SIP        = 12'h144,
        CSR_SATP       = 12'h180
    } RXVCSR_id;

    typedef enum logic [3:0] {
        MCAUSE_INSTR_MISALIGN = 4'd0,
        MCAUSE_INSTR_ACCESS_FAULT = 4'd1,
        MCAUSE_ILLEGAL_INSTR = 4'd2,
        MCAUSE_BREAKPOINT = 4'd3,
        MCAUSE_LOAD_MISALIGN = 4'd4,
        MCAUSE_LOAD_ACCESS_FAULT = 4'd5,
        MCAUSE_STORE_MISALIGN = 4'd6,
        MCAUSE_STORE_ACCESS_FAULT = 4'd7,
        MCAUSE_U_ECALL = 4'd8,
        MCAUSE_S_ECALL = 4'd9,
        MCAUSE_M_ECALL = 4'd11,
        MCAUSE_INSTR_PAGE_FAULT = 4'd12,
        MCAUSE_LOAD_PAGE_FAULT = 4'd13,
        MCAUSE_STORE_PAGE_FAULT = 4'd15
    } MCAUSE_id;

    typedef struct packed {
        logic [31:2] pc;
        logic [31:0] val;
        MCAUSE_id cause;
        logic valid;
    } RXVException;

    typedef struct packed {
        logic mpie;
        logic mie;
    } mstatus;

    function mstatus pack_mstatus;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mstatus.mpie = v[7];
            pack_mstatus.mie  = v[3];
        end
    endfunction

    function logic [31:0] unpack_mstatus;
        input mstatus v;
        begin
            unpack_mstatus = {24'b0, v.mpie, 3'b0, v.mie, 3'b0};
        end
    endfunction

    typedef enum logic {
        MTVEC_DIRECT   = 1'b0,
        MTVEC_VECTORED = 1'b1
    } mtvec_mode;

    typedef struct packed {
        logic [31:2] base;
        mtvec_mode   mode;
    } mtvec;

    function mtvec pack_mtvec;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mtvec.base = v[31:2];
            pack_mtvec.mode = mtvec_mode'(v[0]);
        end
    endfunction

    function logic [31:0] unpack_mtvec;
        input mtvec v;
        begin
            unpack_mtvec = {v.base, 1'b0, v.mode};
        end
    endfunction

    typedef struct packed {logic [31:2] addr;} mepc;

    function mepc pack_mepc;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mepc.addr = v[31:2];
        end
    endfunction

    function logic [31:0] unpack_mepc;
        input mepc v;
        begin
            unpack_mepc = {v.addr, 2'b0};
        end
    endfunction

    typedef struct packed {
        logic is_interrupt;
        logic [3:0] cause;
    } mcause;

    function mcause pack_mcause;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mcause.is_interrupt = v[31];
            pack_mcause.cause        = v[3:0];
        end
    endfunction

    function logic [31:0] unpack_mcause;
        input mcause v;
        begin
            unpack_mcause = {v.is_interrupt, 27'b0, v.cause};
        end
    endfunction

    typedef struct packed {logic [31:0] val;} mtval;

    function mtval pack_mtval;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mtval.val = v[31:0];
        end
    endfunction

    function logic [31:0] unpack_mtval;
        input mtval v;
        begin
            unpack_mtval = v.val;
        end
    endfunction

endpackage
