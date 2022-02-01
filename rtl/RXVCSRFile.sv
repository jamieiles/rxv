`default_nettype none

import RXVCSR::RXVCSR_id;
import RXVCSR::mstatus_t;
import RXVCSR::mtvec_t;
import RXVCSR::mepc_t;
import RXVCSR::mcause_t;
import RXVCSR::mtval_t;
import RXVCSR::mie_t;
import RXVCSR::mip_t;
import RXVCSR::pack_mstatus;
import RXVCSR::unpack_mstatus;
import RXVCSR::pack_mtvec;
import RXVCSR::unpack_mtvec;
import RXVCSR::pack_mepc;
import RXVCSR::unpack_mepc;
import RXVCSR::pack_mcause;
import RXVCSR::unpack_mcause;
import RXVCSR::pack_mtval;
import RXVCSR::unpack_mtval;
import RXVCSR::pack_mie;
import RXVCSR::unpack_mie;
import RXVCSR::pack_mip;
import RXVCSR::unpack_mip;
import RXVCSR::RXVException;
import RXVCSR::MCAUSE_id;
import RXVCSR::MINT_id;
import RXVCSR::mtvec_dest;
import RXVTrace::trace_write_csr;
import RXVTrace::trace_irq;
import RXVTypes::commit_width;

module RXVCSRFile #(
    parameter logic [31:0] vendorid = 0,
    parameter logic [31:0] archid   = 0,
    parameter logic [31:0] impid    = 0
) (
    input  logic                           clk,
    input  logic                           reset,
    // Read port
    input  logic        [            11:0] rd_addr,
    output logic        [            31:0] rd_data,
    // Write port
    input  logic        [commit_width-1:0] writeback_id,
    input  logic        [            11:0] wr_addr,
    input  logic        [            31:0] wr_data,
    input  logic                           wr_en,
    // Decode
    output logic                           valid_csr_out,
    // Exception handling
    output logic        [            31:2] mepc_out,
    output mtvec_t                         mtvec_out,
    output mcause_t                        mcause_out,
    input  RXVException                    exec_exception,
    input  logic        [commit_width-1:0] exec_except_id,
    input  RXVException                    lsu_exception,
    input  logic        [commit_width-1:0] lsu_except_id,
    input  logic                           exception_return,
    output logic                           irq_pending,
    input  logic                           fetch_idle,
    input  logic                           commit_empty,
    input  logic        [            31:2] irq_epc,
    output logic                           irq_resteer,
    output logic        [            31:2] irq_resteer_tgt,
    // Time
    input  logic        [            63:0] mtime,
    input  logic                           mtime_irq,
    // PMU
    output logic                           cyclesh_wren,
    output logic                           cyclesl_wren,
    output logic                           instreth_wren,
    output logic                           instretl_wren,
    input  logic        [            63:0] pmu_cycles,
    input  logic        [            63:0] pmu_instret
);

    localparam logic [31:0] misa_m = 32'd1 << 12;
    localparam logic [31:0] misa_i = 32'd1 << 8;
    localparam logic [31:0] misa_a = 32'd1 << 0;
    localparam logic [31:0] misa = (32'd1 << 30) | misa_m | misa_i | misa_a;

    logic        [31:0] rd_data_next;
    logic        [31:0] mscratch;
    logic               mscratch_wren;
    logic               irq_pending_next;

    mstatus_t           mstatus_reg;
    logic               mstatus_wren;
    mtvec_t             mtvec_reg;
    logic               mtvec_wren;
    mepc_t              mepc_reg;
    logic               mepc_wren;
    mcause_t            mcause_reg;
    logic               mcause_wren;
    mtval_t             mtval_reg;
    logic               mtval_wren;
    mie_t               mie_reg;
    logic               mie_wren;
    mip_t               mip_reg;
    logic               mip_wren;

    logic               exception_write;
    mepc_t              mepc_next;
    mtval_t             mtval_next;
    mcause_t            mcause_next;
    mstatus_t           mstatus_next;
    mtvec_t             mtvec_next;
    mie_t               mie_next;
    mip_t               mip_next;

    RXVException        exception;
    RXVException        irq_exception;
    logic               irq_resteer_next;
    logic        [31:2] irq_resteer_tgt_next;
    logic               take_irq;

    always_comb begin
        logic [3:0] cause;

        cause = 4'b0;
        if (mip_reg.meip & mie_reg.meie) cause = RXVCSR::MINT_M_EXT;
        if (mip_reg.mtip & mie_reg.mtie) cause = RXVCSR::MINT_M_TIMER;
        if (mip_reg.msip & mie_reg.msie) cause = RXVCSR::MINT_M_SW;

        take_irq             = irq_pending & fetch_idle & commit_empty & ~irq_resteer &
                               ~lsu_exception.valid & ~exec_exception.valid;

        irq_exception.pc = irq_epc;
        irq_exception.val = 32'b0;
        irq_exception.valid = take_irq;
        irq_exception.cause = cause;
        irq_exception.irq = 1'b1;

        irq_resteer_next = take_irq;
        irq_resteer_tgt_next = mtvec_dest(mtvec_reg, mcause_next);
    end

    always_ff @(posedge clk) begin
        if (take_irq)
            trace_irq(2'b11, unpack_mcause(mcause_next), unpack_mstatus(mstatus_next), unpack_mepc(
                      mepc_next));
    end

    always_comb begin
        exception = irq_exception;
        if (exec_exception.valid) exception = exec_exception;
        if (lsu_exception.valid) exception = lsu_exception;

        exception_write = exception.valid;
    end

    RXVAssert #(
        .message("no simultaneous exceptions raised")
    ) simultaneous_except (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(lsu_exception.valid & exec_exception.valid))
    );

    always_comb begin
        unique case (rd_addr)
            RXVCSR::CSR_MISA: rd_data_next = misa;
            RXVCSR::CSR_MVENDORID: rd_data_next = vendorid;
            RXVCSR::CSR_MARCHID: rd_data_next = archid;
            RXVCSR::CSR_MIMPID: rd_data_next = impid;
            RXVCSR::CSR_MSCRATCH: rd_data_next = mscratch;
            RXVCSR::CSR_MSTATUS: rd_data_next = unpack_mstatus(mstatus_reg);
            RXVCSR::CSR_MTVEC: rd_data_next = unpack_mtvec(mtvec_reg);
            RXVCSR::CSR_MEPC: rd_data_next = unpack_mepc(mepc_reg);
            RXVCSR::CSR_MCAUSE: rd_data_next = unpack_mcause(mcause_reg);
            RXVCSR::CSR_MTVAL: rd_data_next = unpack_mtval(mtval_reg);
            RXVCSR::CSR_MIE: rd_data_next = unpack_mie(mie_reg);
            RXVCSR::CSR_MIP: rd_data_next = unpack_mip(mip_reg);
            RXVCSR::CSR_UCYCLE: rd_data_next = pmu_cycles[31:0];
            RXVCSR::CSR_UCYCLEH: rd_data_next = pmu_cycles[63:32];
            RXVCSR::CSR_MCYCLE: rd_data_next = pmu_cycles[31:0];
            RXVCSR::CSR_MCYCLEH: rd_data_next = pmu_cycles[63:32];
            RXVCSR::CSR_MINSTRET: rd_data_next = pmu_instret[31:0];
            RXVCSR::CSR_MINSTRETH: rd_data_next = pmu_instret[63:32];
            RXVCSR::CSR_UTIME: rd_data_next = mtime[31:0];
            RXVCSR::CSR_UTIMEH: rd_data_next = mtime[63:32];
            default: rd_data_next = 32'b0;
        endcase
    end

    always_comb begin
        mscratch_wren = wr_en && wr_addr == RXVCSR::CSR_MSCRATCH;
        mtvec_wren = wr_en && wr_addr == RXVCSR::CSR_MTVEC;
        cyclesl_wren = wr_en && wr_addr == RXVCSR::CSR_MCYCLE;
        cyclesh_wren = wr_en && wr_addr == RXVCSR::CSR_MCYCLEH;
        instretl_wren = wr_en && wr_addr == RXVCSR::CSR_MINSTRET;
        instreth_wren = wr_en && wr_addr == RXVCSR::CSR_MINSTRETH;
        mie_wren = wr_en && wr_addr == RXVCSR::CSR_MIE;
        mip_wren = wr_en && wr_addr == RXVCSR::CSR_MIP;
        mstatus_wren  = exception_write || exception_return || (wr_en && wr_addr == RXVCSR::CSR_MSTATUS);
        mepc_wren = exception_write || (wr_en && wr_addr == RXVCSR::CSR_MEPC);
        mcause_wren = exception_write || (wr_en && wr_addr == RXVCSR::CSR_MCAUSE);
        mtval_wren = (exception_write && !take_irq) || (wr_en && wr_addr == RXVCSR::CSR_MTVAL);
    end

    always_comb begin
        mepc_next = pack_mepc(wr_data);
        if (exception_write) mepc_next.addr = exception.pc;
    end

    always_comb begin
        mcause_next = pack_mcause(wr_data);
        if (exception_write) begin
            mcause_next.is_interrupt = exception.irq;
            mcause_next.cause        = exception.cause;
        end
    end

    always_comb begin
        mtval_next = pack_mtval(wr_data);
        if (exception_write) mtval_next.val = exception.val;
    end

    always_comb begin
        if (exception_write) begin
            mstatus_next      = mstatus_reg;
            mstatus_next.mpie = mstatus_next.mie;
            mstatus_next.mie  = 1'b0;
        end else if (exception_return) begin
            mstatus_next      = mstatus_reg;
            mstatus_next.mie  = mstatus_next.mpie;
            mstatus_next.mpie = 1'b0;
        end else begin
            mstatus_next = pack_mstatus(wr_data);
        end
    end

    always_comb begin
        mtvec_next = pack_mtvec(wr_data);
    end

    always_comb begin
        mie_next = pack_mie(wr_data);
    end

    always_comb begin
        mip_next = mip_reg;
        if (mip_wren) mip_next = pack_mip(wr_data);
        mip_next.mtip = mtime_irq;
    end

    always_comb begin
        irq_pending_next = mstatus_reg.mie & |(mip_reg & mie_reg) & ~exception.valid;
    end

    always_comb begin
        unique case (rd_addr)
            RXVCSR::CSR_MVENDORID, RXVCSR::CSR_MARCHID, RXVCSR::CSR_MIMPID,
            RXVCSR::CSR_MSCRATCH, RXVCSR::CSR_MSTATUS, RXVCSR::CSR_MTVEC,
            RXVCSR::CSR_MEPC, RXVCSR::CSR_MCAUSE, RXVCSR::CSR_MTVAL,
            RXVCSR::CSR_MCYCLE, RXVCSR::CSR_MCYCLEH, RXVCSR::CSR_MINSTRET,
            RXVCSR::CSR_MINSTRETH, RXVCSR::CSR_MHARTID, RXVCSR::CSR_SATP,
            RXVCSR::CSR_MIE, RXVCSR::CSR_MIP, RXVCSR::CSR_MEDELEG,
            RXVCSR::CSR_MIDELEG, RXVCSR::CSR_MISA, RXVCSR::CSR_UCYCLE,
            RXVCSR::CSR_UCYCLEH, RXVCSR::CSR_TSELECT, RXVCSR::CSR_TDATA1,
            RXVCSR::CSR_TDATA2, RXVCSR::CSR_TDATA3, RXVCSR::CSR_UTIME,
            RXVCSR::CSR_UTIMEH:
            valid_csr_out = 1'b1;
            default: valid_csr_out = 1'b0;
        endcase
    end

    always_comb begin
        mepc_out = mepc_reg.addr;
    end

    always_comb begin
        mtvec_out = mtvec_reg;
    end

    always_comb begin
        mcause_out = mcause_reg;
    end

    RXVAssert #(
        .message("no write to read-only CSRs")
    ) no_write_ro_csr (
        .clk      (clk),
        .en       (wr_addr[11:10] == 2'b11),
        .condition(!wr_en)
    );

`ifdef verilator
    logic [commit_width-1:0] except_id;
    logic [commit_width-1:0] writer_id;

    always_comb begin
        except_id = exec_except_id;

        if (lsu_exception.valid) except_id = lsu_except_id;

        writer_id = exception_write ? except_id : writeback_id;
    end

    always_ff @(posedge clk) begin
        int trace_id = 32'(writer_id);
        if (mscratch_wren) trace_write_csr(trace_id, RXVCSR::CSR_MSCRATCH, wr_data);
        if (cyclesl_wren) trace_write_csr(trace_id, RXVCSR::CSR_MCYCLE, wr_data);
        if (cyclesh_wren) trace_write_csr(trace_id, RXVCSR::CSR_MCYCLEH, wr_data);
        if (instretl_wren) trace_write_csr(trace_id, RXVCSR::CSR_MINSTRET, wr_data);
        if (instretl_wren) trace_write_csr(trace_id, RXVCSR::CSR_MINSTRETH, wr_data);
        if (mstatus_wren)
            trace_write_csr(trace_id, RXVCSR::CSR_MSTATUS, unpack_mstatus(mstatus_next));
        if (mtvec_wren) trace_write_csr(trace_id, RXVCSR::CSR_MTVEC, unpack_mtvec(mtvec_next));
        if (mepc_wren) trace_write_csr(trace_id, RXVCSR::CSR_MEPC, unpack_mepc(mepc_next));
        if (mcause_wren) trace_write_csr(trace_id, RXVCSR::CSR_MCAUSE, unpack_mcause(mcause_next));
        if (mtval_wren) trace_write_csr(trace_id, RXVCSR::CSR_MTVAL, unpack_mtval(mtval_next));
        if (mie_wren) trace_write_csr(trace_id, RXVCSR::CSR_MIE, unpack_mie(mie_next));
        if (mip_wren) trace_write_csr(trace_id, RXVCSR::CSR_MIP, unpack_mie(mip_next));
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
        .width($bits(mstatus_reg))
    ) mstatus_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mstatus_wren),
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
        .width($bits(mepc_reg))
    ) mepc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mepc_wren),
        .d    (mepc_next),
        .q    (mepc_reg)
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
        .width($bits(mtval_reg))
    ) mtval_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mtval_wren),
        .d    (mtval_next),
        .q    (mtval_reg)
    );

    RXVDFF #(
        .width($bits(mie_reg))
    ) mie_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mie_wren),
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

endmodule
