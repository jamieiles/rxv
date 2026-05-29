// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
package RXVCSR;

    import RXVMMU::asid_bits;

    typedef enum logic [11:0] {
        CSR_MVENDORID      = 12'hF11,
        CSR_MARCHID        = 12'hF12,
        CSR_MIMPID         = 12'hF13,
        CSR_MHARTID        = 12'hF14,
        CSR_MCONFIGPTR     = 12'hF15,
        CSR_SCOUNTOVF      = 12'hDA0,
        CSR_UCYCLE         = 12'hC00,
        CSR_UTIME          = 12'hC01,
        CSR_UINSTRET       = 12'hC02,
        CSR_HPMCOUNTER3    = 12'hc03,
        CSR_HPMCOUNTER31   = 12'hc1f,
        CSR_HPMCOUNTER3H   = 12'hc83,
        CSR_HPMCOUNTER31H  = 12'hc9f,
        CSR_UCYCLEH        = 12'hC80,
        CSR_UTIMEH         = 12'hC81,
        CSR_UINSTRETH      = 12'hC82,
        CSR_MCYCLE         = 12'hB00,
        CSR_MCYCLEH        = 12'hB80,
        CSR_MINSTRET       = 12'hB02,
        CSR_MINSTRETH      = 12'hB82,
        CSR_MHPMEVENT3H    = 12'h723,
        CSR_MHPMEVENT31H   = 12'h73f,
        CSR_TSELECT        = 12'h7A0,
        CSR_TDATA1         = 12'h7A1,
        CSR_TDATA2         = 12'h7A2,
        CSR_TDATA3         = 12'h7A3,
        CSR_STPVAL         = 12'h5C0,
        CSR_STPERMS        = 12'h5C1,
        CSR_MSTATUS        = 12'h300,
        CSR_MISA           = 12'h301,
        CSR_MEDELEG        = 12'h302,
        CSR_MIDELEG        = 12'h303,
        CSR_MIE            = 12'h304,
        CSR_MTVEC          = 12'h305,
        CSR_MENVCFG        = 12'h30a,
        CSR_MENVCFGH       = 12'h31a,
        CSR_MCOUNTEREN     = 12'h306,
        CSR_MCOUNTINHIBIT  = 12'h320,
        CSR_MHPMEVENT3     = 12'h323,
        CSR_MHPMEVENT31    = 12'h33f,
        CSR_MHPMCOUNTER3   = 12'hb03,
        CSR_MHPMCOUNTER31  = 12'hb1f,
        CSR_MHPMCOUNTER3H  = 12'hb83,
        CSR_MHPMCOUNTER31H = 12'hb9f,
        CSR_MSCRATCH       = 12'h340,
        CSR_MEPC           = 12'h341,
        CSR_MCAUSE         = 12'h342,
        CSR_MTVAL          = 12'h343,
        CSR_MIP            = 12'h344,
        CSR_PMPCFG0        = 12'h3a0,
        CSR_PMPCFG1        = 12'h3a1,
        CSR_PMPADDR0       = 12'h3b0,
        CSR_PMPADDR1       = 12'h3b1,
        CSR_PMPADDR2       = 12'h3b2,
        CSR_PMPADDR3       = 12'h3b3,
        CSR_PMPADDR4       = 12'h3b4,
        CSR_PMPADDR5       = 12'h3b5,
        CSR_PMPADDR6       = 12'h3b6,
        CSR_PMPADDR7       = 12'h3b7,
        CSR_MSTATUSH       = 12'h310,
        CSR_SSTATUS        = 12'h100,
        CSR_SEDELEG        = 12'h102,
        CSR_SIDELEG        = 12'h103,
        CSR_SIE            = 12'h104,
        CSR_STVEC          = 12'h105,
        CSR_SCOUNTEREN     = 12'h106,
        CSR_HCOUNTEREN     = 12'h606,
        CSR_SSCRATCH       = 12'h140,
        CSR_SEPC           = 12'h141,
        CSR_SCAUSE         = 12'h142,
        CSR_STVAL          = 12'h143,
        CSR_SIP            = 12'h144,
        CSR_STIMECMP       = 12'h14d,
        CSR_STIMECMPH      = 12'h15d,
        CSR_SATP           = 12'h180,
        CSR_SENVCFG        = 12'h10a,
        CSR_RXV_EMUCTL     = 12'h800
    } RXVCSR_id;

    typedef enum logic [3:0] {
        CAUSE_INSTR_MISALIGN = 4'd0,
        CAUSE_INSTR_ACCESS_FAULT = 4'd1,
        CAUSE_ILLEGAL_INSTR = 4'd2,
        CAUSE_BREAKPOINT = 4'd3,
        CAUSE_LOAD_MISALIGN = 4'd4,
        CAUSE_LOAD_ACCESS_FAULT = 4'd5,
        CAUSE_STORE_MISALIGN = 4'd6,
        CAUSE_STORE_ACCESS_FAULT = 4'd7,
        CAUSE_U_ECALL = 4'd8,
        CAUSE_S_ECALL = 4'd9,
        CAUSE_M_ECALL = 4'd11,
        CAUSE_INSTR_PAGE_FAULT = 4'd12,
        CAUSE_LOAD_PAGE_FAULT = 4'd13,
        CAUSE_STORE_PAGE_FAULT = 4'd15
    } CAUSE_id  /* verilator public */;

    typedef enum logic [3:0] {
        MINT_S_SW = 4'd1,
        MINT_M_SW = 4'd3,
        MINT_S_TIMER = 4'd5,
        MINT_M_TIMER = 4'd7,
        MINT_S_EXT = 4'd9,
        MINT_M_EXT = 4'd11,
        MINT_LCOFI = 4'd13
    } MINT_id  /* verilator public */;

    typedef enum logic [1:0] {
        PRIV_U = 2'b00,
        PRIV_S = 2'b01,
        PRIV_M = 2'b11
    } privilege_t  /* verilator public */;

    typedef struct packed {
        logic pmp_read;
        logic pmp_write;
        logic pmp_exec;
        logic page_global;
        logic page_user;
        logic page_read;
        logic page_write;
        logic page_exec;
        logic walk_violation;
    } stperms_t;

    typedef struct packed {
        logic [31:2] pc;
        logic [31:0] val;
        logic [31:0] pval;
        logic [3:0] cause;
        logic valid;
        logic irq;
        stperms_t perms;
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

    function CAUSE_id exception_cause;
        // verilator public
        input RXVException e;

        exception_cause = CAUSE_id'(e.cause);
    endfunction

    function logic exception_valid;
        // verilator public
        input RXVException e;

        exception_valid = e.valid;
    endfunction

    // verilator lint_on UNUSED

    typedef struct packed {
        logic [1:0] mpp;
        logic spp;
        logic mpie;
        logic spie;
        logic mie;
        logic sie;
        logic tsr;
        logic tw;
        logic tvm;
        logic mxr;
        logic m_sum;
        logic mprv;
    } mstatus_t;

    function mstatus_t pack_mstatus;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        input mstatus_t orig;
        // verilator lint_on UNUSED
        begin
            pack_mstatus.tsr   = v[22];
            pack_mstatus.tw    = v[21];
            pack_mstatus.tvm   = v[20];
            pack_mstatus.mxr   = v[19];
            pack_mstatus.m_sum = v[18];
            pack_mstatus.mprv  = v[17];
            pack_mstatus.mpp   = v[12:11];
            if (v[12:11] == 2'b10) pack_mstatus.mpp = orig.mpp;
            pack_mstatus.spp  = v[8];
            pack_mstatus.mpie = v[7];
            pack_mstatus.spie = v[5];
            pack_mstatus.mie  = v[3];
            pack_mstatus.sie  = v[1];
        end
    endfunction

    function mstatus_t pack_sstatus;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        input mstatus_t orig;
        // verilator lint_on UNUSED
        begin
            pack_sstatus       = orig;
            pack_sstatus.mxr   = v[19];
            pack_sstatus.m_sum = v[18];
            pack_sstatus.spp   = v[8];
            pack_sstatus.spie  = v[5];
            pack_sstatus.sie   = v[1];
        end
    endfunction

    function logic [31:0] unpack_mstatus;
        input mstatus_t v;
        begin
            unpack_mstatus = {
                9'b0,
                v.tsr,
                v.tw,
                v.tvm,
                v.mxr,
                v.m_sum,
                v.mprv,
                4'b0,
                v.mpp,
                2'b0,
                v.spp,
                v.mpie,
                1'b0,
                v.spie,
                1'b0,
                v.mie,
                1'b0,
                v.sie,
                1'b0
            };
        end
    endfunction

    function logic [31:0] unpack_sstatus;
        // verilator lint_off UNUSED
        input mstatus_t v;
        // verilator lint_on UNUSED
        begin
            unpack_sstatus = {12'b0, v.mxr, v.m_sum, 9'b0, v.spp, 2'b0, v.spie, 3'b0, v.sie, 1'b0};
        end
    endfunction

    typedef struct packed {
        logic ssie;
        logic msie;
        logic stie;
        logic mtie;
        logic seie;
        logic meie;
        logic lcofie;
    } mie_t;

    function mie_t pack_mie;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mie.ssie   = v[1];
            pack_mie.msie   = v[3];
            pack_mie.stie   = v[5];
            pack_mie.mtie   = v[7];
            pack_mie.seie   = v[9];
            pack_mie.meie   = v[11];
            pack_mie.lcofie = v[13];
        end
    endfunction

    function logic [31:0] unpack_mie;
        input mie_t v;
        begin
            unpack_mie = {
                18'b0,
                v.lcofie,
                1'b0,
                v.meie,
                1'b0,
                v.seie,
                1'b0,
                v.mtie,
                1'b0,
                v.stie,
                1'b0,
                v.msie,
                1'b0,
                v.ssie,
                1'b0
            };
        end
    endfunction

    function mie_t pack_sie;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        input mie_t orig;
        // verilator lint_on UNUSED
        begin
            pack_sie        = orig;
            pack_sie.ssie   = v[1];
            pack_sie.stie   = v[5];
            pack_sie.seie   = v[9];
            pack_sie.lcofie = v[13];
        end
    endfunction

    function logic [31:0] unpack_sie;
        // verilator lint_off UNUSED
        input mie_t v;
        // verilator lint_on UNUSED
        begin
            unpack_sie = {18'b0, v.lcofie, 3'b0, v.seie, 3'b0, v.stie, 3'b0, v.ssie, 1'b0};
        end
    endfunction

    typedef struct packed {
        logic ssip;
        logic msip;
        logic stip;
        logic mtip;
        logic seip;
        logic meip;
        logic lcofip;
    } mip_t;

    function mip_t pack_mip;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mip.ssip   = v[1];
            pack_mip.msip   = v[3];
            pack_mip.stip   = v[5];
            pack_mip.mtip   = v[7];
            pack_mip.seip   = v[9];
            pack_mip.meip   = v[11];
            pack_mip.lcofip = v[13];
        end
    endfunction

    function logic [31:0] unpack_mip;
        input mip_t v;
        begin
            unpack_mip = {
                18'b0,
                v.lcofip,
                1'b0,
                v.meip,
                1'b0,
                v.seip,
                1'b0,
                v.mtip,
                1'b0,
                v.stip,
                1'b0,
                v.msip,
                1'b0,
                v.ssip,
                1'b0
            };
        end
    endfunction

    function mip_t pack_sip;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        input mip_t orig;
        // verilator lint_on UNUSED
        begin
            pack_sip        = orig;
            pack_sip.ssip   = v[1];
            pack_sip.stip   = v[5];
            pack_sip.seip   = v[9];
            pack_sip.lcofip = v[13];
        end
    endfunction

    function logic [31:0] unpack_sip;
        // verilator lint_off UNUSED
        input mip_t v;
        // verilator lint_on UNUSED
        begin
            unpack_sip = {18'b0, v.lcofip, 3'b0, v.seip, 3'b0, v.stip, 3'b0, v.ssip, 1'b0};
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

    typedef enum logic {
        STVEC_DIRECT   = 1'b0,
        STVEC_VECTORED = 1'b1
    } stvec_mode;

    typedef struct packed {
        logic [31:2] base;
        stvec_mode   mode;
    } stvec_t;

    function stvec_t pack_stvec;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_stvec.mode = stvec_mode'(v[0]);
            // Vectored mode is aligned to 64 bytes so that the cause can be
            // OR'd in
            if (pack_stvec.mode == STVEC_DIRECT) pack_stvec.base = v[31:2];
            else pack_stvec.base = {v[31:6], 4'b0};
        end
    endfunction

    function logic [31:0] unpack_stvec;
        input stvec_t v;
        begin
            unpack_stvec = {v.base, 1'b0, v.mode};
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

    typedef struct packed {logic [31:2] addr;} sepc_t;

    function sepc_t pack_sepc;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_sepc.addr = v[31:2];
        end
    endfunction

    function logic [31:0] unpack_sepc;
        input sepc_t v;
        begin
            unpack_sepc = {v.addr, 2'b0};
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

    typedef struct packed {
        logic is_interrupt;
        logic [3:0] cause;
    } scause_t;

    function scause_t pack_scause;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_scause.is_interrupt = v[31];
            pack_scause.cause        = v[3:0];
        end
    endfunction

    function logic [31:0] unpack_scause;
        input scause_t v;
        begin
            unpack_scause = {v.is_interrupt, 27'b0, v.cause};
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

    typedef struct packed {logic [31:0] val;} stval_t;

    function stval_t pack_stval;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_stval.val = v[31:0];
        end
    endfunction

    function logic [31:0] unpack_stval;
        input stval_t v;
        begin
            unpack_stval = v.val;
        end
    endfunction

    typedef struct packed {logic [31:0] pval;} stpval_t;

    function stpval_t pack_stpval;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_stpval.pval = v[31:0];
        end
    endfunction

    function logic [31:0] unpack_stpval;
        input stpval_t v;
        begin
            unpack_stpval = v.pval;
        end
    endfunction

    function stperms_t pack_stperms;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_stperms.pmp_read       = v[0];
            pack_stperms.pmp_write      = v[1];
            pack_stperms.pmp_exec       = v[2];
            pack_stperms.page_global    = v[3];
            pack_stperms.page_user      = v[4];
            pack_stperms.page_read      = v[5];
            pack_stperms.page_write     = v[6];
            pack_stperms.page_exec      = v[7];
            pack_stperms.walk_violation = v[8];
        end
    endfunction

    function logic [31:0] unpack_stperms;
        input stperms_t v;
        begin
            unpack_stperms = {
                23'b0,
                v.walk_violation,
                v.page_exec,
                v.page_write,
                v.page_read,
                v.page_user,
                v.page_global,
                v.pmp_exec,
                v.pmp_write,
                v.pmp_read
            };
        end
    endfunction

    typedef struct packed {
        logic instr_misalign;
        logic instr_access_fault;
        logic illegal_instr;
        logic breakpoint;
        logic load_misalign;
        logic load_access_fault;
        logic store_misalign;
        logic store_access_fault;
        logic u_ecall;
        logic s_ecall;
        logic instr_page_fault;
        logic load_page_fault;
        logic store_page_fault;
    } medeleg_t;

    function medeleg_t pack_medeleg;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_medeleg.instr_misalign     = v[0];
            pack_medeleg.instr_access_fault = v[1];
            pack_medeleg.illegal_instr      = v[2];
            pack_medeleg.breakpoint         = v[3];
            pack_medeleg.load_misalign      = v[4];
            pack_medeleg.load_access_fault  = v[5];
            pack_medeleg.store_misalign     = v[6];
            pack_medeleg.store_access_fault = v[7];
            pack_medeleg.u_ecall            = v[8];
            pack_medeleg.s_ecall            = v[9];
            pack_medeleg.instr_page_fault   = v[12];
            pack_medeleg.load_page_fault    = v[13];
            pack_medeleg.store_page_fault   = v[15];
        end
    endfunction

    function logic [31:0] unpack_medeleg;
        input medeleg_t v;
        begin
            unpack_medeleg = {
                16'b0,
                v.store_page_fault,
                1'b0,
                v.load_page_fault,
                v.instr_page_fault,
                2'b0,
                v.s_ecall,
                v.u_ecall,
                v.store_access_fault,
                v.store_misalign,
                v.load_access_fault,
                v.load_misalign,
                v.breakpoint,
                v.illegal_instr,
                v.instr_access_fault,
                v.instr_misalign
            };
        end
    endfunction

    typedef struct packed {
        logic mode;
        logic [asid_bits-1:0] asid;
        logic [21:0] ppn;
    } satp_t;

    function satp_t pack_satp;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED

        begin
            pack_satp.mode = v[31];
            pack_satp.asid = v[22+:asid_bits];
            pack_satp.ppn  = v[21:0];
        end
    endfunction

    function logic [31:0] unpack_satp;
        input satp_t v;
        begin
            unpack_satp = {v.mode, {(9 - asid_bits) {1'b0}}, v.asid, v.ppn};
        end
    endfunction

    typedef struct packed {
        logic s_sw;
        logic s_timer;
        logic s_ext;
        logic lcofi;
    } mideleg_t;

    function mideleg_t pack_mideleg;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mideleg.s_sw    = v[1];
            pack_mideleg.s_timer = v[5];
            pack_mideleg.s_ext   = v[9];
            pack_mideleg.lcofi   = v[13];
        end
    endfunction

    function logic [31:0] unpack_mideleg;
        input mideleg_t v;
        begin
            unpack_mideleg = {18'b0, v.lcofi, 3'b0, v.s_ext, 3'b0, v.s_timer, 3'b0, v.s_sw, 1'b0};
        end
    endfunction

    typedef struct packed {
        logic [28:0] hpm;
        logic ir;
        logic tm;
        logic cy;
    } mcounteren_t;

    function mcounteren_t pack_mcounteren;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mcounteren.hpm = v[31:3];
            pack_mcounteren.ir  = v[2];
            pack_mcounteren.tm  = v[1];
            pack_mcounteren.cy  = v[0];
        end
    endfunction

    function logic [31:0] unpack_mcounteren;
        input mcounteren_t v;
        begin
            unpack_mcounteren = {v.hpm, v.ir, v.tm, v.cy};
        end
    endfunction

    typedef struct packed {
        logic [28:0] hpm;
        logic ir;
        logic cy;
    } mcountinhibit_t;

    function mcountinhibit_t pack_mcountinhibit;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mcountinhibit.hpm = v[31:3];
            pack_mcountinhibit.ir  = v[2];
            pack_mcountinhibit.cy  = v[0];
        end
    endfunction

    function logic [31:0] unpack_mcountinhibit;
        input mcountinhibit_t v;
        begin
            unpack_mcountinhibit = {v.hpm, v.ir, 1'b0, v.cy};
        end
    endfunction

    typedef struct packed {
        logic of;
        logic minh;
        logic sinh;
        logic uinh;
    } mhpmeventh_t;

    function mhpmeventh_t pack_mhpmeventh;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mhpmeventh.of   = v[31];
            pack_mhpmeventh.minh = v[30];
            pack_mhpmeventh.sinh = v[29];
            pack_mhpmeventh.uinh = v[28];
        end
    endfunction

    function logic [31:0] unpack_mhpmeventh;
        input mhpmeventh_t v;
        begin
            unpack_mhpmeventh = {v.of, v.minh, v.sinh, v.uinh, 28'b0};
        end
    endfunction

    typedef struct packed {logic [4:0] sel;} mhpmevent_t;

    function mhpmevent_t pack_mhpmevent;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_mhpmevent.sel = v[4:0];
        end
    endfunction

    function logic [31:0] unpack_mhpmevent;
        input mhpmevent_t v;
        begin
            unpack_mhpmevent = {27'b0, v.sel};
        end
    endfunction

    typedef struct packed {logic [28:0] ovf;} scountovf_t;

    function scountovf_t pack_scountovf;
        // verilator lint_off UNUSED
        input logic [31:0] v;
        // verilator lint_on UNUSED
        begin
            pack_scountovf.ovf = v[31:3];
        end
    endfunction

    function logic [31:0] unpack_scountovf;
        input scountovf_t v;
        begin
            unpack_scountovf = {v.ovf, 3'b0};
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

    function logic [31:2] stvec_dest;
        input stvec_t vec;
        input mcause_t cause;

        begin
            if (!cause.is_interrupt || vec.mode == STVEC_DIRECT) stvec_dest = vec.base;
            else stvec_dest = vec.base | 30'(cause.cause);
        end
    endfunction

    function privilege_t effective_privilege;
        // verilator lint_off UNUSED
        input mstatus_t m;
        // verilator lint_on UNUSED
        input privilege_t current_privilege;

        begin
            effective_privilege = current_privilege;
            if (m.mprv) effective_privilege = privilege_t'(m.mpp);
        end
    endfunction

endpackage
