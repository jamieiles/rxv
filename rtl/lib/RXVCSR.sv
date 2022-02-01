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
    } MCAUSE_id  /* verilator public */;

    typedef enum logic [3:0] {
        MINT_M_SW = 4'd3,
        MINT_M_TIMER = 4'd7,
        MINT_M_EXT = 4'd11
    } MINT_id  /* verilator public */;

    typedef struct packed {
        logic [31:2] pc;
        logic [31:0] val;
        logic [3:0] cause;
        logic valid;
        logic irq;
    } RXVException;

    // verilator lint_off UNUSED

    function logic [31:2] exception_pc;
        // verilator public
        input RXVException e;

        exception_pc = e.pc;
    endfunction

    function logic [31:0] exception_val;
        // verilator public
        input RXVException e;

        exception_val = e.val;
    endfunction

    function MCAUSE_id exception_cause;
        // verilator public
        input RXVException e;

        exception_cause = e.cause;
    endfunction

    function logic exception_valid;
        // verilator public
        input RXVException e;

        exception_valid = e.valid;
    endfunction

    // verilator lint_on UNUSED

    typedef struct packed {
        logic [1:0] mpp;
        logic mpie;
        logic mie;
    } mstatus_t;

    function mstatus_t pack_mstatus;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mstatus.mpp = v[12:11];
            if (pack_mstatus.mpp != 2'b11) pack_mstatus.mpp = 2'b11;
            pack_mstatus.mpie = v[7];
            pack_mstatus.mie  = v[3];
        end
    endfunction

    function logic [31:0] unpack_mstatus;
        input mstatus_t v;
        begin
            unpack_mstatus = {19'b0, v.mpp, 3'b0, v.mpie, 3'b0, v.mie, 3'b0};
        end
    endfunction

    typedef struct packed {
        logic msie;
        logic mtie;
        logic meie;
    } mie_t;

    function mie_t pack_mie;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mie.msie = v[3];
            pack_mie.mtie = v[7];
            pack_mie.meie = v[11];
        end
    endfunction

    function logic [31:0] unpack_mie;
        input mie_t v;
        begin
            unpack_mie = {20'b0, v.meie, 3'b0, v.mtie, 3'b0, v.msie, 3'b0};
        end
    endfunction

    typedef struct packed {
        logic msip;
        logic mtip;
        logic meip;
    } mip_t;

    function mip_t pack_mip;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mip.msip = v[3];
            pack_mip.mtip = v[7];
            pack_mip.meip = v[11];
        end
    endfunction

    function logic [31:0] unpack_mip;
        input mip_t v;
        begin
            unpack_mip = {20'b0, v.meip, 3'b0, v.mtip, 3'b0, v.msip, 3'b0};
        end
    endfunction

    typedef enum logic {
        MTVEC_DIRECT   = 1'b0,
        MTVEC_VECTORED = 1'b1
    } mtvec_mode;

    typedef struct packed {
        logic [31:2] base;
        mtvec_mode   mode;
    } mtvec_t;

    function mtvec_t pack_mtvec;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mtvec.mode = mtvec_mode'(v[0]);
            // Vectored mode is aligned to 64 bytes so that the cause can be
            // OR'd in
            if (pack_mtvec.mode == MTVEC_DIRECT) pack_mtvec.base = v[31:2];
            else pack_mtvec.base = {v[31:6], 4'b0};
        end
    endfunction

    function logic [31:0] unpack_mtvec;
        input mtvec_t v;
        begin
            unpack_mtvec = {v.base, 1'b0, v.mode};
        end
    endfunction

    typedef struct packed {logic [31:2] addr;} mepc_t;

    function mepc_t pack_mepc;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mepc.addr = v[31:2];
        end
    endfunction

    function logic [31:0] unpack_mepc;
        input mepc_t v;
        begin
            unpack_mepc = {v.addr, 2'b0};
        end
    endfunction

    typedef struct packed {
        logic is_interrupt;
        logic [3:0] cause;
    } mcause_t;

    function mcause_t pack_mcause;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mcause.is_interrupt = v[31];
            pack_mcause.cause        = v[3:0];
        end
    endfunction

    function logic [31:0] unpack_mcause;
        input mcause_t v;
        begin
            unpack_mcause = {v.is_interrupt, 27'b0, v.cause};
        end
    endfunction

    typedef struct packed {logic [31:0] val;} mtval_t;

    function mtval_t pack_mtval;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mtval.val = v[31:0];
        end
    endfunction

    function logic [31:0] unpack_mtval;
        input mtval_t v;
        begin
            unpack_mtval = v.val;
        end
    endfunction

    function logic [31:2] mtvec_dest;
        input mtvec_t vec;
        input mcause_t cause;

        begin
            if (!cause.is_interrupt || vec.mode == MTVEC_DIRECT) mtvec_dest = vec.base;
            else mtvec_dest = vec.base | 30'(cause.cause);
        end
    endfunction

endpackage
