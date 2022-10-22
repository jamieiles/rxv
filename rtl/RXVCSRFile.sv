`include "RXV.svh"

import RXVCSR::RXVCSR_id;
import RXVCSR::mstatus_t;
import RXVCSR::mtvec_t;
import RXVCSR::stvec_t;
import RXVCSR::mepc_t;
import RXVCSR::sepc_t;
import RXVCSR::mcause_t;
import RXVCSR::scause_t;
import RXVCSR::mtval_t;
import RXVCSR::stval_t;
import RXVCSR::satp_t;
import RXVCSR::mie_t;
import RXVCSR::mip_t;
import RXVCSR::medeleg_t;
import RXVCSR::mideleg_t;
import RXVCSR::mcounteren_t;
import RXVCSR::mcountinhibit_t;
import RXVCSR::mhpmevent_t;
import RXVCSR::mhpmeventh_t;
import RXVCSR::stpval_t;
import RXVCSR::stperms_t;
import RXVCSR::scountovf_t;
import RXVCSR::pack_mstatus;
import RXVCSR::unpack_mstatus;
import RXVCSR::pack_sstatus;
import RXVCSR::unpack_sstatus;
import RXVCSR::pack_mtvec;
import RXVCSR::unpack_mtvec;
import RXVCSR::pack_stvec;
import RXVCSR::unpack_stvec;
import RXVCSR::pack_mepc;
import RXVCSR::unpack_mepc;
import RXVCSR::pack_sepc;
import RXVCSR::unpack_sepc;
import RXVCSR::pack_mcause;
import RXVCSR::unpack_mcause;
import RXVCSR::pack_scause;
import RXVCSR::unpack_scause;
import RXVCSR::pack_mtval;
import RXVCSR::unpack_mtval;
import RXVCSR::pack_stval;
import RXVCSR::unpack_stval;
import RXVCSR::pack_mie;
import RXVCSR::unpack_mie;
import RXVCSR::pack_mip;
import RXVCSR::unpack_mip;
import RXVCSR::pack_sie;
import RXVCSR::unpack_sie;
import RXVCSR::pack_sip;
import RXVCSR::unpack_sip;
import RXVCSR::pack_medeleg;
import RXVCSR::unpack_medeleg;
import RXVCSR::pack_mideleg;
import RXVCSR::unpack_mideleg;
import RXVCSR::pack_mcounteren;
import RXVCSR::unpack_mcounteren;
import RXVCSR::pack_mcountinhibit;
import RXVCSR::unpack_mcountinhibit;
import RXVCSR::pack_mhpmevent;
import RXVCSR::unpack_mhpmevent;
import RXVCSR::pack_mhpmeventh;
import RXVCSR::unpack_mhpmeventh;
import RXVCSR::pack_satp;
import RXVCSR::unpack_satp;
import RXVCSR::pack_stpval;
import RXVCSR::unpack_stpval;
import RXVCSR::pack_stperms;
import RXVCSR::unpack_stperms;
import RXVCSR::pack_scountovf;
import RXVCSR::unpack_scountovf;
import RXVCSR::RXVException;
import RXVCSR::MINT_id;
import RXVCSR::mtvec_dest;
import RXVCSR::stvec_dest;
import RXVCSR::privilege_t;
import RXVCSR::effective_privilege;
import RXVTrace::trace_write_csr;
import RXVTrace::trace_irq;
import RXVTypes::commit_width;
import RXVTypes::pmu_evt_sel;
import RXVMMU::asid_bits;

module RXVCSRFile #(
    parameter logic [31:0] vendorid           = 0,
    parameter logic [31:0] archid             = 0,
    parameter logic [31:0] impid              = 0,
    parameter logic [11:0] num_event_counters = 8
) (
    input  logic                                 clk,
    input  logic                                 reset,
    // Read port
    input  logic        [                  11:0] rd_addr,
    output logic        [                  31:0] rd_data,
    // Write port
    input  logic        [      commit_width-1:0] writeback_id,
    input  logic        [                  11:0] wr_addr,
    input  logic        [                  31:0] wr_data,
    input  logic                                 wr_en,
    // Decode
    output logic                                 valid_csr_out,
    // Exception handling
    output logic        [                  31:2] mepc_out,
    output logic        [                  31:2] sepc_out,
    output mstatus_t                             mstatus_out,
    output logic        [                  31:2] exception_resteer_tgt,
    input  RXVException                          exec_exception,
    input  logic        [      commit_width-1:0] exec_except_id,
    input  logic                                 exception_priv_change,
    input  RXVException                          lsu_exception,
    input  logic        [      commit_width-1:0] lsu_except_id,
    input  logic                                 do_mret,
    input  logic                                 do_sret,
    output logic                                 irq_pending,
    input  logic                                 fetch_idle,
    input  logic                                 commit_empty,
    input  logic                                 exception_pending,
    input  logic        [                  31:2] irq_epc,
    output logic                                 irq_resteer,
    output logic        [                  31:2] irq_resteer_tgt,
    // Time
    input  logic        [                  63:0] mtime,
    input  logic                                 mtime_irq,
    input  logic                                 ext_irq,
    // PMU
    output logic                                 cyclesh_wren,
    output logic                                 cyclesl_wren,
    output logic                                 pmu_cycles_inhibit,
    output logic                                 instreth_wren,
    output logic                                 instretl_wren,
    output logic                                 pmu_instret_inhibit,
    input  logic        [                  63:0] pmu_cycles,
    input  logic        [                  63:0] pmu_instret,
    output privilege_t                           current_privilege,
    output logic                                 m_mode,
    output logic                                 s_mode,
    output logic                                 u_mode,
    output logic        [num_event_counters-1:0] pmu_m_inhibit,
    output logic        [num_event_counters-1:0] pmu_s_inhibit,
    output logic        [num_event_counters-1:0] pmu_u_inhibit,
    output pmu_evt_sel  [num_event_counters-1:0] pmu_event_sel,
    output logic        [num_event_counters-1:0] pmu_event_inhibit,
    input  logic        [                  63:0] pmu_count [0:num_event_counters-1],
    output logic        [num_event_counters-1:0] pmu_count_wren,
    output logic        [num_event_counters-1:0] pmu_counth_wren,
    output logic        [                  31:0] pmu_count_wrval,
    // verilator lint_off UNUSED
    input  logic        [num_event_counters-1:0] pmu_overflow,
    // verilator lint_on UNUSED
    // PMP
    output logic        [                   1:0] pmp_addr_idx,
    input  logic        [                  31:0] pmp_addr,
    input  logic        [                  31:0] pmp_cfg,
    output logic                                 pmp_update_cfg,
    output logic                                 pmp_update_addr,
    output logic        [                   1:0] pmp_update_addr_idx,
    // MMU
    output logic        [                 31:12] translation_base,
    output logic        [         asid_bits-1:0] active_asid,
    output logic                                 i_tlb_enabled,
    output logic                                 d_tlb_enabled
);

    localparam counter_bits = $clog2(num_event_counters);

    localparam logic [31:0] misa_u = 32'd1 << 20;
    localparam logic [31:0] misa_s = 32'd1 << 18;
    localparam logic [31:0] misa_m = 32'd1 << 12;
    localparam logic [31:0] misa_i = 32'd1 << 8;
    localparam logic [31:0] misa_a = 32'd1 << 0;
    localparam logic [31:0] misa = (32'd1 << 30) | misa_m | misa_i | misa_a | misa_s | misa_u;

    logic           [                          31:0] rd_data_next;
    logic           [                          31:0] mscratch;
    logic                                            mscratch_wren;
    logic           [                          31:0] sscratch;
    logic                                            sscratch_wren;
    logic                                            irq_pending_next;

    mstatus_t                                        mstatus_reg;
    logic                                            mstatus_wren;
    logic                                            sstatus_wren;
    logic                                            update_mstatus;
    logic                                            update_mie;
    mtvec_t                                          mtvec_reg;
    logic                                            mtvec_wren;
    stvec_t                                          stvec_reg;
    logic                                            stvec_wren;
    mepc_t                                           mepc_reg;
    logic                                            mepc_wren;
    sepc_t                                           sepc_reg;
    logic                                            sepc_wren;
    mcause_t                                         mcause_reg;
    logic                                            mcause_wren;
    scause_t                                         scause_reg;
    logic                                            scause_wren;
    mtval_t                                          mtval_reg;
    logic                                            mtval_wren;
    mtval_t                                          stval_reg;
    logic                                            stval_wren;
    stpval_t                                         stpval_reg;
    logic                                            stpval_wren;
    stperms_t                                        stperms_reg;
    logic                                            stperms_wren;
    mie_t                                            mie_reg;
    logic                                            mie_wren;
    logic                                            sie_wren;
    mip_t                                            mip_reg;
    logic                                            mip_wren;
    logic                                            sip_wren;
    medeleg_t                                        medeleg_reg;
    logic                                            medeleg_wren;
    mideleg_t                                        mideleg_reg;
    logic                                            mideleg_wren;
    mcounteren_t                                     mcounteren_reg;
    logic                                            mcounteren_wren;
    mcountinhibit_t                                  mcountinhibit_reg;
    logic                                            mcountinhibit_wren;
    satp_t                                           satp_reg;
    logic                                            satp_wren;
    logic           [                          63:0] stimecmp_reg;
    logic           [                          63:0] stimecmp_next;
    logic                                            stimecmp_wren;
    logic                                            stimecmph_wren;
    scountovf_t                                      scountovf_reg;

    logic                                            exception_write;
    mepc_t                                           mepc_next;
    sepc_t                                           sepc_next;
    mtval_t                                          mtval_next;
    mtval_t                                          stval_next;
    stpval_t                                         stpval_next;
    stperms_t                                        stperms_next;
    mcause_t                                         mcause_next;
    scause_t                                         scause_next;
    mstatus_t                                        mstatus_next;
    mtvec_t                                          mtvec_next;
    stvec_t                                          stvec_next;
    mie_t                                            mie_next;
    mip_t                                            mip_next;
    medeleg_t                                        medeleg_next;
    mideleg_t                                        mideleg_next;
    mcounteren_t                                     mcounteren_next;
    mcountinhibit_t                                  mcountinhibit_next;
    satp_t                                           satp_next;

    RXVException                                     exception;
    RXVException                                     irq_exception;
    logic                                            irq_resteer_next;
    logic           [                          31:2] irq_resteer_tgt_next;
    logic           [                          31:2] exception_resteer_tgt_next;
    logic                                            take_irq;

    privilege_t                                      exception_privilege;
    privilege_t                                      next_privilege;
    privilege_t                                      exception_target_level;
    logic                                            exception_has_val;
    logic                                            exception_has_pval;

    logic           [                          31:0] active_s_irqs;
    logic           [                          31:0] active_m_irqs;

    logic           [  $bits(current_privilege)-1:0] current_privilege_q;
    logic           [$bits(exception_privilege)-1:0] exception_privilege_q;

`ifndef verible_no_format
    mhpmevent_t  [                         num_event_counters-1:0] mhpmevent_reg;
    mhpmevent_t  [                         num_event_counters-1:0] mhpmevent_next;
    logic          [num_event_counters-1:0]                        mhpmevent_wren;
    mhpmeventh_t [                         num_event_counters-1:0] mhpmeventh_reg;
    mhpmeventh_t [                         num_event_counters-1:0] mhpmeventh_next;
    logic          [num_event_counters-1:0]                        mhpmeventh_wren;
`endif

    logic stime_irq;

    always_comb begin
        current_privilege   = privilege_t'(current_privilege_q);
        exception_privilege = privilege_t'(exception_privilege_q);
    end

    always_comb begin
        active_s_irqs = unpack_sie(mie_reg) & unpack_sip(mip_reg) & unpack_mideleg(mideleg_reg);
        active_m_irqs = unpack_mie(mie_reg) & unpack_mip(mip_reg) & ~unpack_mideleg(mideleg_reg);
    end

    always_comb begin
        if ((current_privilege == RXVCSR::PRIV_M && mstatus_reg.mie &&
             ~exception.valid && |active_m_irqs) ||
            (current_privilege != RXVCSR::PRIV_M && ~exception.valid && |active_m_irqs)) begin
            irq_pending_next = 1'b1;
        end else if (current_privilege == RXVCSR::PRIV_S && mstatus_reg.sie &&
                     ~exception.valid && |active_s_irqs) begin
            irq_pending_next = 1'b1;
        end else if (current_privilege == RXVCSR::PRIV_U && ~exception.valid &&
                     |(active_m_irqs | active_s_irqs)) begin
            irq_pending_next = 1'b1;
        end else begin
            irq_pending_next = 1'b0;
        end
    end

    always_comb begin
        logic [3:0] cause;

        cause = 4'b0;
        if (mip_reg.lcofip & mie_reg.lcofie) cause = RXVCSR::MINT_LCOFI;
        if (mip_reg.ssip & mie_reg.ssie) cause = RXVCSR::MINT_S_SW;
        if (mip_reg.stip & mie_reg.stie) cause = RXVCSR::MINT_S_TIMER;
        if (mip_reg.seip & mie_reg.seie) cause = RXVCSR::MINT_S_EXT;
        if (mip_reg.msip & mie_reg.msie) cause = RXVCSR::MINT_M_SW;
        if (mip_reg.mtip & mie_reg.mtie) cause = RXVCSR::MINT_M_TIMER;
        if (mip_reg.meip & mie_reg.meie) cause = RXVCSR::MINT_M_EXT;

        take_irq = irq_pending & fetch_idle & commit_empty & ~irq_resteer &
                   ~lsu_exception.valid & ~exec_exception.valid &
                   ~exception_pending & ~do_mret & ~do_sret;
        if ((current_privilege == RXVCSR::PRIV_M && !mstatus_reg.mie) ||
            (current_privilege == RXVCSR::PRIV_S && !mstatus_reg.sie && ~|active_m_irqs))
            take_irq = 1'b0;

        irq_exception       = RXVException'(1'b0);
        irq_exception.pc    = irq_epc;
        irq_exception.val   = 32'b0;
        irq_exception.valid = take_irq;
        irq_exception.cause = cause;
        irq_exception.irq   = 1'b1;
    end

    always_comb begin
        irq_resteer_next = take_irq;
        irq_resteer_tgt_next = exception_target_level == RXVCSR::PRIV_M ?
            mtvec_dest(mtvec_reg, mcause_next) : stvec_dest(stvec_reg, scause_next);
    end

    always_ff @(posedge clk) begin
        if (take_irq) begin
            if (exception_target_level == RXVCSR::PRIV_M)
                trace_irq(exception_target_level, unpack_mcause(mcause_next), unpack_mstatus(
                        mstatus_next), unpack_mepc(mepc_next));
            else
                trace_irq(exception_target_level, unpack_scause(scause_next), unpack_sstatus(
                    mstatus_next), unpack_sepc(sepc_next));
        end
    end

    always_comb begin
        exception = irq_exception;
        if (exec_exception.valid) exception = exec_exception;
        if (lsu_exception.valid) exception = lsu_exception;

        exception_write = exception.valid;
    end

    always_comb begin
        stime_irq = mtime > stimecmp_reg;
    end

    RXVAssert #(
        .message("no simultaneous exceptions raised")
    ) simultaneous_except (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(lsu_exception.valid & exec_exception.valid))
    );

    always_comb begin
        unique case (rd_addr) inside
            RXVCSR::CSR_MISA: rd_data_next = misa;
            RXVCSR::CSR_MVENDORID: rd_data_next = vendorid;
            RXVCSR::CSR_MARCHID: rd_data_next = archid;
            RXVCSR::CSR_MIMPID: rd_data_next = impid;
            RXVCSR::CSR_MSCRATCH: rd_data_next = mscratch;
            RXVCSR::CSR_MSTATUS: rd_data_next = unpack_mstatus(mstatus_reg);
            RXVCSR::CSR_SSTATUS: rd_data_next = unpack_sstatus(mstatus_reg);
            RXVCSR::CSR_MTVEC: rd_data_next = unpack_mtvec(mtvec_reg);
            RXVCSR::CSR_STVEC: rd_data_next = unpack_stvec(stvec_reg);
            RXVCSR::CSR_MEPC: rd_data_next = unpack_mepc(mepc_reg);
            RXVCSR::CSR_MCAUSE: rd_data_next = unpack_mcause(mcause_reg);
            RXVCSR::CSR_SCAUSE: rd_data_next = unpack_scause(scause_reg);
            RXVCSR::CSR_MTVAL: rd_data_next = unpack_mtval(mtval_reg);
            RXVCSR::CSR_STVAL: rd_data_next = unpack_stval(stval_reg);
            RXVCSR::CSR_STPVAL: rd_data_next = unpack_stpval(stpval_reg);
            RXVCSR::CSR_STPERMS: rd_data_next = unpack_stperms(stperms_reg);
            RXVCSR::CSR_MIE: rd_data_next = unpack_mie(mie_reg);
            RXVCSR::CSR_SIE: rd_data_next = unpack_sie(mie_reg);
            RXVCSR::CSR_MIP: rd_data_next = unpack_mip(mip_reg);
            RXVCSR::CSR_SIP: rd_data_next = unpack_sip(mip_reg);
            RXVCSR::CSR_SSCRATCH: rd_data_next = sscratch;
            RXVCSR::CSR_SATP: rd_data_next = unpack_satp(satp_reg);
            RXVCSR::CSR_UCYCLE: rd_data_next = pmu_cycles[31:0];
            RXVCSR::CSR_UCYCLEH: rd_data_next = pmu_cycles[63:32];
            RXVCSR::CSR_UINSTRET: rd_data_next = pmu_instret[31:0];
            RXVCSR::CSR_UINSTRETH: rd_data_next = pmu_instret[63:32];
            RXVCSR::CSR_MCYCLE: rd_data_next = pmu_cycles[31:0];
            RXVCSR::CSR_MCYCLEH: rd_data_next = pmu_cycles[63:32];
            RXVCSR::CSR_MINSTRET: rd_data_next = pmu_instret[31:0];
            RXVCSR::CSR_MINSTRETH: rd_data_next = pmu_instret[63:32];
            RXVCSR::CSR_MEDELEG: rd_data_next = unpack_medeleg(medeleg_reg);
            RXVCSR::CSR_MIDELEG: rd_data_next = unpack_mideleg(mideleg_reg);
            RXVCSR::CSR_MCOUNTEREN: rd_data_next = unpack_mcounteren(mcounteren_reg);
            RXVCSR::CSR_MCOUNTINHIBIT: rd_data_next = unpack_mcountinhibit(mcountinhibit_reg);
            RXVCSR::CSR_SEPC: rd_data_next = unpack_sepc(sepc_reg);
            RXVCSR::CSR_UTIME: rd_data_next = mtime[31:0];
            RXVCSR::CSR_UTIMEH: rd_data_next = mtime[63:32];
            RXVCSR::CSR_PMPCFG0: rd_data_next = pmp_cfg;
            RXVCSR::CSR_STIMECMP: rd_data_next = stimecmp_reg[31:0];
            RXVCSR::CSR_STIMECMPH: rd_data_next = stimecmp_reg[63:32];
            RXVCSR::CSR_PMPADDR0, RXVCSR::CSR_PMPADDR1, RXVCSR::CSR_PMPADDR2, RXVCSR::CSR_PMPADDR3:
            rd_data_next = pmp_addr;
            [RXVCSR::CSR_MHPMEVENT3 : RXVCSR::CSR_MHPMEVENT3 + num_event_counters - 1]:
            rd_data_next = unpack_mhpmevent(mhpmevent_reg[rd_addr-RXVCSR::CSR_MHPMEVENT3]);
            [RXVCSR::CSR_MHPMEVENT3H : RXVCSR::CSR_MHPMEVENT3H + num_event_counters - 1]:
            rd_data_next = unpack_mhpmeventh(mhpmeventh_reg[rd_addr-RXVCSR::CSR_MHPMEVENT3H]);
            [RXVCSR::CSR_MHPMCOUNTER3 : RXVCSR::CSR_MHPMCOUNTER3 + num_event_counters - 1]:
            rd_data_next = pmu_count[counter_bits'(rd_addr-RXVCSR::CSR_MHPMCOUNTER3)][31:0];
            [RXVCSR::CSR_MHPMCOUNTER3H : RXVCSR::CSR_MHPMCOUNTER3H + num_event_counters - 1]:
            rd_data_next = pmu_count[counter_bits'(rd_addr-RXVCSR::CSR_MHPMCOUNTER3H)][63:32];
            RXVCSR::CSR_SCOUNTOVF: rd_data_next = unpack_scountovf(scountovf_reg);
            default: rd_data_next = 32'b0;
        endcase
    end

    always_comb begin
        unique case (exception.cause)
            RXVCSR::CAUSE_U_ECALL, RXVCSR::CAUSE_S_ECALL, RXVCSR::CAUSE_M_ECALL:
            exception_has_val = 1'b0;
            default: exception_has_val = 1'b1;
        endcase
    end

    always_comb begin
        unique case (exception.cause)
            RXVCSR::CAUSE_INSTR_ACCESS_FAULT, RXVCSR::CAUSE_INSTR_PAGE_FAULT,
            RXVCSR::CAUSE_LOAD_ACCESS_FAULT, RXVCSR::CAUSE_LOAD_PAGE_FAULT,
            RXVCSR::CAUSE_STORE_ACCESS_FAULT, RXVCSR::CAUSE_STORE_PAGE_FAULT: begin
                exception_has_pval = 1'b1;
            end
            default: exception_has_pval = 1'b0;
        endcase
    end

// verilog_format: off
    always_comb begin
        integer evt_i;

        for (evt_i = 0; evt_i < num_event_counters; ++evt_i) begin
            mhpmevent_wren[counter_bits'(evt_i)]  = wr_en && wr_addr == RXVCSR::CSR_MHPMEVENT3 + 12'(evt_i);
            mhpmeventh_wren[counter_bits'(evt_i)] = wr_en && wr_addr == RXVCSR::CSR_MHPMEVENT3H + 12'(evt_i);
            pmu_count_wren[counter_bits'(evt_i)]  = wr_en && wr_addr == RXVCSR::CSR_MHPMCOUNTER3 + 12'(evt_i);
            pmu_counth_wren[counter_bits'(evt_i)] = wr_en && wr_addr == RXVCSR::CSR_MHPMCOUNTER3H + 12'(evt_i);
        end

        mscratch_wren = wr_en && wr_addr == RXVCSR::CSR_MSCRATCH;
        mtvec_wren = wr_en && wr_addr == RXVCSR::CSR_MTVEC;
        stvec_wren = wr_en && wr_addr == RXVCSR::CSR_STVEC;
        cyclesl_wren = wr_en && wr_addr == RXVCSR::CSR_MCYCLE;
        cyclesh_wren = wr_en && wr_addr == RXVCSR::CSR_MCYCLEH;
        instretl_wren = wr_en && wr_addr == RXVCSR::CSR_MINSTRET;
        instreth_wren = wr_en && wr_addr == RXVCSR::CSR_MINSTRETH;
        mie_wren = wr_en && wr_addr == RXVCSR::CSR_MIE;
        mip_wren = wr_en && wr_addr == RXVCSR::CSR_MIP;
        sie_wren = wr_en && wr_addr == RXVCSR::CSR_SIE;
        sip_wren = wr_en && wr_addr == RXVCSR::CSR_SIP;
        satp_wren = wr_en && wr_addr == RXVCSR::CSR_SATP;
        medeleg_wren = wr_en && wr_addr == RXVCSR::CSR_MEDELEG;
        mideleg_wren = wr_en && wr_addr == RXVCSR::CSR_MIDELEG;
        mcounteren_wren = wr_en && wr_addr == RXVCSR::CSR_MCOUNTEREN;
        mcountinhibit_wren = wr_en && wr_addr == RXVCSR::CSR_MCOUNTINHIBIT;
        mstatus_wren  = ((exception_write && exception_target_level == RXVCSR::PRIV_M) ||
                         do_mret || (wr_en && wr_addr == RXVCSR::CSR_MSTATUS));
        sstatus_wren  = ((exception_write && exception_target_level == RXVCSR::PRIV_S) ||
                         do_sret || (wr_en && wr_addr == RXVCSR::CSR_SSTATUS));
        mepc_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_M) ||
                     (wr_en && wr_addr == RXVCSR::CSR_MEPC));
        sepc_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_S) ||
                     (wr_en && wr_addr == RXVCSR::CSR_SEPC));
        mcause_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_M) ||
                       (wr_en && wr_addr == RXVCSR::CSR_MCAUSE));
        scause_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_S) ||
                       (wr_en && wr_addr == RXVCSR::CSR_SCAUSE));
        mtval_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_M &&
                       !take_irq && exception_has_val) ||
                      (wr_en && wr_addr == RXVCSR::CSR_MTVAL));
        stval_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_S &&
                       !take_irq && exception_has_val) ||
                      (wr_en && wr_addr == RXVCSR::CSR_STVAL));
        stpval_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_S &&
                        !take_irq && exception_has_pval) ||
                       (wr_en && wr_addr == RXVCSR::CSR_STPVAL));
        stperms_wren = ((exception_write && exception_target_level == RXVCSR::PRIV_S &&
                         !take_irq && exception_has_pval) ||
                        (wr_en && wr_addr == RXVCSR::CSR_STPERMS));
        pmp_update_cfg = wr_en && wr_addr == RXVCSR::CSR_PMPCFG0;
        pmp_update_addr = wr_en && (wr_addr == RXVCSR::CSR_PMPADDR0 ||
                                    wr_addr == RXVCSR::CSR_PMPADDR1 ||
                                    wr_addr == RXVCSR::CSR_PMPADDR2 ||
                                    wr_addr == RXVCSR::CSR_PMPADDR3);
        sscratch_wren = wr_en && wr_addr == RXVCSR::CSR_SSCRATCH;
        stimecmp_wren = wr_en && wr_addr == RXVCSR::CSR_STIMECMP;
        stimecmph_wren = wr_en && wr_addr == RXVCSR::CSR_STIMECMPH;

        update_mstatus = mstatus_wren | sstatus_wren;
        update_mie = mie_wren | sie_wren;
    end
// verilog_format: on

    always_comb begin
        pmu_count_wrval = wr_data;
    end

    always_comb begin
          mepc_next = pack_mepc(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_M)
            mepc_next.addr = exception.pc;
    end

    always_comb begin
        sepc_next = pack_sepc(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_S)
            sepc_next.addr = exception.pc;
    end

    always_comb begin
        mcause_next = pack_mcause(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_M) begin
            mcause_next.is_interrupt = exception.irq;
            mcause_next.cause        = exception.cause;
        end
    end

    always_comb begin
        scause_next = pack_scause(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_S) begin
            scause_next.is_interrupt = exception.irq;
            scause_next.cause        = exception.cause;
        end
    end

    always_comb begin
        mtval_next = pack_mtval(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_M)
            mtval_next.val = exception.val;
    end

    always_comb begin
        stval_next = pack_stval(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_S)
            stval_next.val = exception.val;
    end

    always_comb begin
        stpval_next = pack_stpval(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_S)
            stpval_next.pval = exception.pval;
    end

    always_comb begin
        stperms_next = pack_stperms(wr_data);
        if (exception_write && exception_target_level == RXVCSR::PRIV_S) begin
            stperms_next.pmp_read       = exception.perms.pmp_read;
            stperms_next.pmp_write      = exception.perms.pmp_write;
            stperms_next.pmp_exec       = exception.perms.pmp_exec;
            stperms_next.page_global    = exception.perms.page_global;
            stperms_next.page_user      = exception.perms.page_user;
            stperms_next.page_read      = exception.perms.page_read;
            stperms_next.page_write     = exception.perms.page_write;
            stperms_next.page_exec      = exception.perms.page_exec;
            stperms_next.walk_violation = exception.perms.walk_violation;
        end
    end

    always_comb begin
        satp_next = pack_satp(wr_data);
    end

    always_comb begin
        mstatus_next = mstatus_reg;

        if (exception_write && exception_target_level == RXVCSR::PRIV_M) begin
            mstatus_next.mpie = mstatus_next.mie;
            mstatus_next.mie  = 1'b0;
            mstatus_next.mpp  = current_privilege;
        end else if (exception_write) begin
            mstatus_next.spie = mstatus_next.sie;
            mstatus_next.sie  = 1'b0;
            mstatus_next.spp  = current_privilege[0];
        end else if (do_mret) begin
            mstatus_next.mie  = mstatus_next.mpie;
            mstatus_next.mpie = 1'b0;
            mstatus_next.mpp  = RXVCSR::PRIV_U;
            mstatus_next.mprv = mstatus_reg.mpp != RXVCSR::PRIV_M ? 1'b0 : mstatus_reg.mprv;
        end else if (do_sret) begin
            mstatus_next.sie  = mstatus_next.spie;
            mstatus_next.spie = 1'b0;
            mstatus_next.spp  = 1'b0;
            mstatus_next.mprv = 1'b0;
        end else if (mstatus_wren) begin
            mstatus_next = pack_mstatus(wr_data, mstatus_reg);
        end else if (sstatus_wren) begin
            mstatus_next = pack_sstatus(wr_data, mstatus_reg);
        end
    end

    always_comb begin
        mtvec_next = pack_mtvec(wr_data);
    end

    always_comb begin
        stvec_next = pack_stvec(wr_data);
    end

    always_comb begin
        mie_next = mie_reg;

        if (mie_wren) mie_next = pack_mie(wr_data);
        if (sie_wren) mie_next = pack_sie(wr_data, mie_next);
    end

    always_comb begin
        medeleg_next = pack_medeleg(wr_data);
    end

    always_comb begin
        mideleg_next = pack_mideleg(wr_data);
    end

    always_comb begin
        mcounteren_next = pack_mcounteren(wr_data);
    end

    always_comb begin
        mcountinhibit_next  = pack_mcountinhibit(wr_data);

        pmu_cycles_inhibit  = mcountinhibit_reg.cy;
        pmu_instret_inhibit = mcountinhibit_reg.ir;
    end

    always_comb begin
        integer evt_i;

        mhpmevent_next  = mhpmevent_reg;
        mhpmeventh_next = mhpmeventh_reg;

        for (evt_i = 0; evt_i < num_event_counters; ++evt_i) begin
            if (pmu_overflow[evt_i]) mhpmeventh_next[evt_i].of = 1'b1;
            if (mhpmevent_wren[evt_i]) mhpmevent_next[evt_i] = pack_mhpmevent(wr_data);
            if (mhpmeventh_wren[evt_i]) mhpmeventh_next[evt_i] = pack_mhpmeventh(wr_data);
        end
    end

    always_comb begin
        m_mode = current_privilege == RXVCSR::PRIV_M;
        s_mode = current_privilege == RXVCSR::PRIV_S;
        u_mode = current_privilege == RXVCSR::PRIV_U;
    end

    always_comb begin
        mip_next = mip_reg;
        if (mip_wren) mip_next = pack_mip(wr_data);
        if (sip_wren) mip_next = pack_sip(wr_data, mip_next);
        mip_next.mtip = mtime_irq;
        mip_next.stip = stime_irq;
        mip_next.seip = ext_irq;
        if (|pmu_overflow)
            mip_next.lcofip = 1'b1;
    end

    always_comb begin
        mstatus_out = mstatus_reg;
    end

    always_comb begin
        pmp_addr_idx        = rd_addr[1:0];
        pmp_update_addr_idx = wr_addr[1:0];
    end

    always_comb begin
        stimecmp_next = stimecmp_reg;
        if (stimecmp_wren) stimecmp_next[31:0] = wr_data;
        if (stimecmph_wren) stimecmp_next[63:32] = wr_data;
    end

    always_comb begin
        logic [num_event_counters-1:0] ovf_mask;
        logic [num_event_counters-1:0] ovf_status;

        unique case (current_privilege)
        RXVCSR::PRIV_M: ovf_mask = {num_event_counters{1'b1}};
        RXVCSR::PRIV_S: ovf_mask = mcounteren_reg.hpm[num_event_counters-1:0];
        default: ovf_mask = {num_event_counters{1'b0}};
        endcase

        for (int i = 0; i < num_event_counters; ++i)
            ovf_status[i] = mhpmeventh_reg[i].of;
        scountovf_reg = pack_scountovf({{(29-num_event_counters){1'b0}}, ovf_status & ovf_mask, 3'b0});
    end

    // verilog_format: off
    always_comb begin
        unique case (rd_addr) inside
            // Debug
            RXVCSR::CSR_TSELECT, RXVCSR::CSR_TDATA1, RXVCSR::CSR_TDATA2, RXVCSR::CSR_TDATA3,
            // Machine
            RXVCSR::CSR_MVENDORID, RXVCSR::CSR_MARCHID, RXVCSR::CSR_MIMPID,
            RXVCSR::CSR_MSCRATCH, RXVCSR::CSR_MSTATUS, RXVCSR::CSR_MTVEC,
            RXVCSR::CSR_MEPC, RXVCSR::CSR_MCAUSE, RXVCSR::CSR_MTVAL,
            RXVCSR::CSR_MCYCLE, RXVCSR::CSR_MCYCLEH, RXVCSR::CSR_MINSTRET,
            RXVCSR::CSR_MINSTRETH, RXVCSR::CSR_MHARTID, RXVCSR::CSR_MIE,
            RXVCSR::CSR_MIP, RXVCSR::CSR_MEDELEG, RXVCSR::CSR_MIDELEG,
            RXVCSR::CSR_MISA, RXVCSR::CSR_PMPCFG0, RXVCSR::CSR_PMPADDR0,
            RXVCSR::CSR_PMPADDR1, RXVCSR::CSR_PMPADDR2, RXVCSR::CSR_PMPADDR3,
            RXVCSR::CSR_MCOUNTEREN, RXVCSR::CSR_MCOUNTINHIBIT, RXVCSR::CSR_MSTATUSH,
            RXVCSR::CSR_MENVCFG, RXVCSR::CSR_MENVCFGH, RXVCSR::CSR_MCONFIGPTR,
            // Supervisor
            RXVCSR::CSR_SSTATUS, RXVCSR::CSR_SEDELEG, RXVCSR::CSR_SIDELEG, RXVCSR::CSR_SIE,
            RXVCSR::CSR_SIP, RXVCSR::CSR_STVEC, RXVCSR::CSR_SCOUNTEREN, RXVCSR::CSR_SSCRATCH,
            RXVCSR::CSR_SEPC, RXVCSR::CSR_SCAUSE, RXVCSR::CSR_STVAL, RXVCSR::CSR_STPVAL,
            RXVCSR::CSR_STPERMS, RXVCSR::CSR_STIMECMP, RXVCSR::CSR_STIMECMPH,
            RXVCSR::CSR_SCOUNTOVF, RXVCSR::CSR_SENVCFG,
            // User
            RXVCSR::CSR_UCYCLE, RXVCSR::CSR_UCYCLEH, RXVCSR::CSR_UTIME, RXVCSR::CSR_UTIMEH,
            RXVCSR::CSR_UINSTRET, RXVCSR::CSR_UINSTRETH:
            valid_csr_out = 1'b1;
            // SATP special case for TVM
            RXVCSR::CSR_SATP:
            valid_csr_out = current_privilege == RXVCSR::PRIV_M || (current_privilege == RXVCSR::PRIV_S && !mstatus_reg.tvm);
            [RXVCSR::CSR_MHPMEVENT3 : RXVCSR::CSR_MHPMEVENT3 + num_event_counters - 1]:
            valid_csr_out = 1'b1;
            [RXVCSR::CSR_MHPMEVENT3H : RXVCSR::CSR_MHPMEVENT3H + num_event_counters - 1]:
            valid_csr_out = 1'b1;
            [RXVCSR::CSR_MHPMCOUNTER3 : RXVCSR::CSR_MHPMCOUNTER3 + num_event_counters - 1]:
            valid_csr_out = 1'b1;
            [RXVCSR::CSR_MHPMCOUNTER3H : RXVCSR::CSR_MHPMCOUNTER3H + num_event_counters - 1]:
            valid_csr_out = 1'b1;
            default: valid_csr_out = 1'b0;
        endcase

`ifdef verilator
        if (rd_addr == RXVCSR::CSR_RXV_EMUCTL) valid_csr_out = 1'b1;
`endif

        if (current_privilege == RXVCSR::PRIV_S && rd_addr[9:8] == 2'b11) valid_csr_out = 1'b0;
        if (current_privilege == RXVCSR::PRIV_U && rd_addr[9:8] != 2'b00) valid_csr_out = 1'b0;

        if (current_privilege != RXVCSR::PRIV_M) begin
            unique case (rd_addr)
                RXVCSR::CSR_UTIME, RXVCSR::CSR_UTIMEH: valid_csr_out = mcounteren_reg.tm;
                RXVCSR::CSR_UCYCLE, RXVCSR::CSR_UCYCLEH: valid_csr_out = mcounteren_reg.cy;
                RXVCSR::CSR_UINSTRET, RXVCSR::CSR_UINSTRETH: valid_csr_out = mcounteren_reg.ir;
                default: ;
            endcase
        end
    end
    // verilog_format: on


    always_comb begin
        mepc_out = mepc_reg.addr;
    end

    always_comb begin
        sepc_out = sepc_reg.addr;
    end

    always_comb begin
        logic [31:0] medeleg_raw;
        logic [31:0] mideleg_raw;

        exception_target_level = RXVCSR::PRIV_M;

        medeleg_raw            = unpack_medeleg(medeleg_reg);
        mideleg_raw            = unpack_mideleg(mideleg_reg);

        if (exception.valid && !exception.irq && medeleg_raw[32'(exception.cause)])
            exception_target_level = current_privilege == RXVCSR::PRIV_M ? RXVCSR::PRIV_M : RXVCSR::PRIV_S;
        if (exception.valid && exception.irq && mideleg_raw[32'(exception.cause)])
            exception_target_level = RXVCSR::PRIV_S;
    end

    always_comb begin
        exception_resteer_tgt_next = exception_target_level == RXVCSR::PRIV_M ?
            mtvec_dest(mtvec_reg, mcause_next) : stvec_dest(stvec_reg, scause_next);
    end

    always_comb begin
        next_privilege = current_privilege;
        if (do_mret) next_privilege = privilege_t'(mstatus_reg.mpp);
        if (do_sret) next_privilege = privilege_t'(mstatus_reg.spp);
        if (exception_priv_change || irq_resteer) next_privilege = exception_privilege;
    end

    always_comb begin
        translation_base = satp_reg.ppn[19:0];
        active_asid = satp_reg.asid[asid_bits-1:0];
        d_tlb_enabled = satp_reg.mode &&
            effective_privilege(mstatus_reg, current_privilege) != RXVCSR::PRIV_M;
        i_tlb_enabled = satp_reg.mode && current_privilege != RXVCSR::PRIV_M;
    end

    RXVAssert #(
        .message("no write to read-only CSRs")
    ) no_write_ro_csr (
        .clk      (clk),
        .en       (wr_addr[11:10] == 2'b11),
        .condition(!wr_en)
    );

`ifdef verilator
    RXVAssert #(
        .message("exception lowers privilege level")
    ) no_exception_to_lower_level (
        .clk      (clk),
        .en       (exception_write),
        .condition(!(current_privilege == RXVCSR::PRIV_M && next_privilege == RXVCSR::PRIV_S))
    );

    always_ff @(posedge clk) begin
        if (wr_en && wr_addr == RXVCSR::CSR_RXV_EMUCTL) begin
            $display("rxvemu: received simulation exit CSR write (%08x)", wr_data);
            $finish();
        end
    end
`endif

`ifdef verilator
    logic [commit_width-1:0] except_id;
    integer trace_id;

    always_comb begin
        except_id = exec_except_id;

        if (lsu_exception.valid) except_id = lsu_except_id;

        trace_id = take_irq ? -1 : (exception_write ? integer'(except_id) : integer'(writeback_id));
    end

    always_ff @(posedge clk) begin
        integer evt_i;

        if (!take_irq) begin
            if (mscratch_wren) trace_write_csr(trace_id, RXVCSR::CSR_MSCRATCH, wr_data);
            if (cyclesl_wren) trace_write_csr(trace_id, RXVCSR::CSR_MCYCLE, wr_data);
            if (cyclesh_wren) trace_write_csr(trace_id, RXVCSR::CSR_MCYCLEH, wr_data);
            if (instretl_wren) trace_write_csr(trace_id, RXVCSR::CSR_MINSTRET, wr_data);
            if (instreth_wren) trace_write_csr(trace_id, RXVCSR::CSR_MINSTRETH, wr_data);
            if (mstatus_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_MSTATUS, unpack_mstatus(mstatus_next));
            if (mtvec_wren) trace_write_csr(trace_id, RXVCSR::CSR_MTVEC, unpack_mtvec(mtvec_next));
            if (stvec_wren) trace_write_csr(trace_id, RXVCSR::CSR_STVEC, unpack_stvec(stvec_next));
            if (mepc_wren) trace_write_csr(trace_id, RXVCSR::CSR_MEPC, unpack_mepc(mepc_next));
            if (mcause_wren) trace_write_csr(trace_id, RXVCSR::CSR_MCAUSE, unpack_mcause(mcause_next));
            if (scause_wren) trace_write_csr(trace_id, RXVCSR::CSR_SCAUSE, unpack_scause(scause_next));
            if (mtval_wren) trace_write_csr(trace_id, RXVCSR::CSR_MTVAL, unpack_mtval(mtval_next));
            if (stval_wren) trace_write_csr(trace_id, RXVCSR::CSR_STVAL, unpack_stval(stval_next));
            if (stpval_wren) trace_write_csr(trace_id, RXVCSR::CSR_STPVAL, unpack_stpval(stpval_next));
            if (stperms_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_STPERMS, unpack_stperms(stperms_next));
            if (mie_wren) trace_write_csr(trace_id, RXVCSR::CSR_MIE, unpack_mie(mie_next));
            if (mip_wren) trace_write_csr(trace_id, RXVCSR::CSR_MIP, unpack_mie(mip_next));
            if (sie_wren) trace_write_csr(trace_id, RXVCSR::CSR_SIE, unpack_sie(mie_next));
            if (sip_wren) trace_write_csr(trace_id, RXVCSR::CSR_SIP, unpack_sie(mip_next));
            if (medeleg_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_MEDELEG, unpack_medeleg(medeleg_next));
            if (mideleg_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_MIDELEG, unpack_mideleg(mideleg_next));
            if (mcounteren_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_MCOUNTEREN, unpack_mcounteren(mcounteren_next));
            if (mcountinhibit_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_MCOUNTINHIBIT, unpack_mcountinhibit(
                                mcountinhibit_next));
            if (sscratch_wren) trace_write_csr(trace_id, RXVCSR::CSR_SSCRATCH, wr_data);
            if (sepc_wren) trace_write_csr(trace_id, RXVCSR::CSR_SEPC, unpack_sepc(sepc_next));
            if (sstatus_wren)
                trace_write_csr(trace_id, RXVCSR::CSR_SSTATUS, unpack_sstatus(mstatus_next));
            if (satp_wren) trace_write_csr(trace_id, RXVCSR::CSR_SATP, unpack_satp(satp_next));
            if (pmp_update_cfg) trace_write_csr(trace_id, RXVCSR::CSR_PMPCFG0, wr_data);
            if (wr_en && wr_addr == RXVCSR::CSR_PMPADDR0)
                trace_write_csr(trace_id, RXVCSR::CSR_PMPADDR0, wr_data);
            if (wr_en && wr_addr == RXVCSR::CSR_PMPADDR1)
                trace_write_csr(trace_id, RXVCSR::CSR_PMPADDR1, wr_data);
            if (wr_en && wr_addr == RXVCSR::CSR_PMPADDR2)
                trace_write_csr(trace_id, RXVCSR::CSR_PMPADDR2, wr_data);
            if (wr_en && wr_addr == RXVCSR::CSR_PMPADDR3)
                trace_write_csr(trace_id, RXVCSR::CSR_PMPADDR3, wr_data);
            if (wr_en && wr_addr == RXVCSR::CSR_STIMECMP)
                trace_write_csr(trace_id, RXVCSR::CSR_STIMECMP, wr_data);
            if (wr_en && wr_addr == RXVCSR::CSR_STIMECMPH)
                trace_write_csr(trace_id, RXVCSR::CSR_STIMECMPH, wr_data);

            for (evt_i = 0; evt_i < num_event_counters; ++evt_i) begin
                if (mhpmevent_wren[counter_bits'(evt_i)])
                    trace_write_csr(trace_id, RXVCSR::CSR_MHPMEVENT3 + 12'(evt_i), wr_data);
                if (mhpmeventh_wren[counter_bits'(evt_i)])
                    trace_write_csr(trace_id, RXVCSR::CSR_MHPMEVENT3H + 12'(evt_i), wr_data);
                if (pmu_count_wren[counter_bits'(evt_i)])
                    trace_write_csr(trace_id, RXVCSR::CSR_MHPMCOUNTER3 + 12'(evt_i), wr_data);
                if (pmu_counth_wren[counter_bits'(evt_i)])
                    trace_write_csr(trace_id, RXVCSR::CSR_MHPMCOUNTER3H + 12'(evt_i), wr_data);
            end
        end
    end
`endif  // verilator

    RXVDFF #(
        .width(32)
    ) rd_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_data_next),
        .q    (rd_data)
    );

    RXVDFF #(
        .width(32)
    ) mscratch_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mscratch_wren),
        .d    (wr_data),
        .q    (mscratch)
    );

    RXVDFF #(
        .width(32)
    ) sscratch_dff (
        .clk  (clk),
        .reset(reset),
        .en   (sscratch_wren),
        .d    (wr_data),
        .q    (sscratch)
    );

    RXVDFF #(
        .width($bits(mstatus_reg))
    ) mstatus_dff (
        .clk  (clk),
        .reset(reset),
        .en   (update_mstatus),
        .d    (mstatus_next),
        .q    (mstatus_reg)
    );

    RXVDFF #(
        .width($bits(mtvec_reg))
    ) mtvec_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mtvec_wren),
        .d    (mtvec_next),
        .q    (mtvec_reg)
    );

    RXVDFF #(
        .width($bits(stvec_reg))
    ) stvec_dff (
        .clk  (clk),
        .reset(reset),
        .en   (stvec_wren),
        .d    (stvec_next),
        .q    (stvec_reg)
    );

    RXVDFF #(
        .width($bits(mepc_reg))
    ) mepc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mepc_wren),
        .d    (mepc_next),
        .q    (mepc_reg)
    );

    RXVDFF #(
        .width($bits(sepc_reg))
    ) sepc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (sepc_wren),
        .d    (sepc_next),
        .q    (sepc_reg)
    );

    RXVDFF #(
        .width($bits(mcause_reg))
    ) mcause_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mcause_wren),
        .d    (mcause_next),
        .q    (mcause_reg)
    );

    RXVDFF #(
        .width($bits(scause_reg))
    ) scause_dff (
        .clk  (clk),
        .reset(reset),
        .en   (scause_wren),
        .d    (scause_next),
        .q    (scause_reg)
    );

    RXVDFF #(
        .width($bits(mtval_reg))
    ) mtval_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mtval_wren),
        .d    (mtval_next),
        .q    (mtval_reg)
    );

    RXVDFF #(
        .width($bits(stval_reg))
    ) stval_dff (
        .clk  (clk),
        .reset(reset),
        .en   (stval_wren),
        .d    (stval_next),
        .q    (stval_reg)
    );

    RXVDFF #(
        .width($bits(stpval_reg))
    ) stpval_dff (
        .clk  (clk),
        .reset(reset),
        .en   (stpval_wren),
        .d    (stpval_next),
        .q    (stpval_reg)
    );

    RXVDFF #(
        .width($bits(stperms_reg))
    ) stperms_dff (
        .clk  (clk),
        .reset(reset),
        .en   (stperms_wren),
        .d    (stperms_next),
        .q    (stperms_reg)
    );

    RXVDFF #(
        .width($bits(mie_reg))
    ) mie_dff (
        .clk  (clk),
        .reset(reset),
        .en   (update_mie),
        .d    (mie_next),
        .q    (mie_reg)
    );

    RXVDFF #(
        .width($bits(mip_reg))
    ) mip_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (mip_next),
        .q    (mip_reg)
    );

    RXVDFF #(
        .width($bits(medeleg_reg))
    ) medeleg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (medeleg_wren),
        .d    (medeleg_next),
        .q    (medeleg_reg)
    );

    RXVDFF #(
        .width($bits(mideleg_reg))
    ) mideleg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mideleg_wren),
        .d    (mideleg_next),
        .q    (mideleg_reg)
    );

    RXVDFF #(
        .width($bits(mcounteren_reg))
    ) mcounteren_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mcounteren_wren),
        .d    (mcounteren_next),
        .q    (mcounteren_reg)
    );

    RXVDFF #(
        .width($bits(mcountinhibit_reg))
    ) mcountinhibit_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mcountinhibit_wren),
        .d    (mcountinhibit_next),
        .q    (mcountinhibit_reg)
    );

    RXVDFF #(
        .width($bits(satp_reg))
    ) satp_dff (
        .clk  (clk),
        .reset(reset),
        .en   (satp_wren),
        .d    (satp_next),
        .q    (satp_reg)
    );

    RXVDFF irq_pending_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (irq_pending_next),
        .q    (irq_pending)
    );

    RXVDFF #(
        .width(30)
    ) irq_resteer_tgt_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (irq_resteer_tgt_next),
        .q    (irq_resteer_tgt)
    );

    RXVDFF irq_resteer_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (irq_resteer_next),
        .q    (irq_resteer)
    );

    RXVDFF #(
        .width(30)
    ) exception_resteer_tgt_dff (
        .clk  (clk),
        .reset(reset),
        .en   (exception_write),
        .d    (exception_resteer_tgt_next),
        .q    (exception_resteer_tgt)
    );

    RXVDFF #(
        .width    ($bits(current_privilege)),
        .reset_val(RXVCSR::PRIV_M)
    ) current_privilege_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_privilege),
        .q    (current_privilege_q)
    );

    RXVDFF #(
        .width($bits(exception_privilege))
    ) exception_privilege_dff (
        .clk  (clk),
        .reset(reset),
        .en   (exception_write),
        .d    (exception_target_level),
        .q    (exception_privilege_q)
    );

    RXVDFF #(
        .width($bits(stimecmp_reg))
    ) stimecmp_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (stimecmp_next),
        .q    (stimecmp_reg)
    );

    genvar i;
    generate
        for (i = 0; i < num_event_counters; ++i) begin : event_counters
            RXVDFF #(
                .width($bits(mhpmevent_t))
            ) mhpmevent_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (mhpmevent_next[i]),
                .q    (mhpmevent_reg[i])
            );

            RXVDFF #(
                .width($bits(mhpmeventh_t))
            ) mhpmeventh_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (mhpmeventh_next[i]),
                .q    (mhpmeventh_reg[i])
            );

            assign pmu_m_inhibit[i]     = mhpmeventh_reg[i].minh;
            assign pmu_s_inhibit[i]     = mhpmeventh_reg[i].sinh;
            assign pmu_u_inhibit[i]     = mhpmeventh_reg[i].uinh;
            assign pmu_event_sel[i]     = mhpmevent_reg[i].sel;
            assign pmu_event_inhibit[i] = mcountinhibit_reg.hpm[i];
        end
    endgenerate

endmodule
