`default_nettype none

import RXVCSR::RXVCSR_id;
import RXVCSR::mstatus;
import RXVCSR::mtvec;
import RXVCSR::mepc;
import RXVCSR::mcause;
import RXVCSR::mtval;
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
import RXVCSR::RXVException;
import RXVCSR::MCAUSE_id;
import RXVTrace::trace_write_csr;

module RXVCSRFile #(
    parameter logic [31:0] vendorid     = 0,
    parameter logic [31:0] archid       = 0,
    parameter logic [31:0] impid        = 0,
    parameter int          commit_order = 3
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
    output mtvec                           mtvec_out,
    output mcause                          mcause_out,
    input  RXVException                    exec_exception,
    input  logic        [commit_width-1:0] exec_except_id,
    input  RXVException                    lsu_exception,
    input  logic        [commit_width-1:0] lsu_except_id,
    // PMU
    output logic                           cyclesh_wren,
    output logic                           cyclesl_wren,
    output logic                           instreth_wren,
    output logic                           instretl_wren,
    input  logic        [            63:0] pmu_cycles,
    input  logic        [            63:0] pmu_instret
);

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic        [            31:0] rd_data_next;
    logic        [            31:0] mscratch;
    logic                           mscratch_wren;

    mstatus                         mstatus_reg;
    logic                           mstatus_wren;
    mtvec                           mtvec_reg;
    logic                           mtvec_wren;
    mepc                            mepc_reg;
    logic                           mepc_wren;
    mcause                          mcause_reg;
    logic                           mcause_wren;
    mtval                           mtval_reg;
    logic                           mtval_wren;

    logic                           exception_write;
    mepc                            mepc_next;
    mtval                           mtval_next;
    mcause                          mcause_next;
    mstatus                         mstatus_next;
    mtvec                           mtvec_next;

    RXVException                    exception;

    always_comb begin
        exception = exec_exception;
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
            RXVCSR::CSR_MVENDORID: rd_data_next = vendorid;
            RXVCSR::CSR_MARCHID: rd_data_next = archid;
            RXVCSR::CSR_MIMPID: rd_data_next = impid;
            RXVCSR::CSR_MSCRATCH: rd_data_next = mscratch;
            RXVCSR::CSR_MSTATUS: rd_data_next = unpack_mstatus(mstatus_reg);
            RXVCSR::CSR_MTVEC: rd_data_next = unpack_mtvec(mtvec_reg);
            RXVCSR::CSR_MEPC: rd_data_next = unpack_mepc(mepc_reg);
            RXVCSR::CSR_MCAUSE: rd_data_next = unpack_mcause(mcause_reg);
            RXVCSR::CSR_MTVAL: rd_data_next = unpack_mtval(mtval_reg);
            RXVCSR::CSR_MCYCLE: rd_data_next = pmu_cycles[31:0];
            RXVCSR::CSR_MCYCLEH: rd_data_next = pmu_cycles[63:32];
            RXVCSR::CSR_MINSTRET: rd_data_next = pmu_instret[31:0];
            RXVCSR::CSR_MINSTRETH: rd_data_next = pmu_instret[63:32];
            default: rd_data_next = 32'b0;
        endcase
    end

    always_comb begin
        mscratch_wren = wr_en && wr_addr == RXVCSR::CSR_MSCRATCH;
        mstatus_wren  = wr_en && wr_addr == RXVCSR::CSR_MSTATUS;
        mtvec_wren    = wr_en && wr_addr == RXVCSR::CSR_MTVEC;
        cyclesl_wren  = wr_en && wr_addr == RXVCSR::CSR_MCYCLE;
        cyclesh_wren  = wr_en && wr_addr == RXVCSR::CSR_MCYCLEH;
        instretl_wren = wr_en && wr_addr == RXVCSR::CSR_MINSTRET;
        instreth_wren = wr_en && wr_addr == RXVCSR::CSR_MINSTRETH;
        mepc_wren     = exception_write || (wr_en && wr_addr == RXVCSR::CSR_MEPC);
        mcause_wren   = exception_write || (wr_en && wr_addr == RXVCSR::CSR_MCAUSE);
        mtval_wren    = exception_write || (wr_en && wr_addr == RXVCSR::CSR_MTVAL);
    end

    always_comb begin
        mepc_next = pack_mepc(wr_data);
        if (exception_write) mepc_next.addr = exception.pc;
    end

    always_comb begin
        mcause_next = pack_mcause(wr_data);
        if (exception_write) begin
            mcause_next.is_interrupt = 1'b0;
            mcause_next.cause        = exception.cause;
        end
    end

    always_comb begin
        mtval_next = pack_mtval(wr_data);
        if (exception_write) mtval_next.val = exception.val;
    end

    always_comb begin
        mstatus_next = pack_mstatus(wr_data);
    end

    always_comb begin
        mtvec_next = pack_mtvec(wr_data);
    end

    always_comb begin
        unique case (rd_addr)
            RXVCSR::CSR_MVENDORID, RXVCSR::CSR_MARCHID, RXVCSR::CSR_MIMPID,
            RXVCSR::CSR_MSCRATCH, RXVCSR::CSR_MSTATUS, RXVCSR::CSR_MTVEC,
            RXVCSR::CSR_MEPC, RXVCSR::CSR_MCAUSE, RXVCSR::CSR_MTVAL,
            RXVCSR::CSR_MCYCLE, RXVCSR::CSR_MCYCLEH, RXVCSR::CSR_MINSTRET,
            RXVCSR::CSR_MINSTRETH, RXVCSR::CSR_MHARTID, RXVCSR::CSR_SATP,
            RXVCSR::CSR_MIE, RXVCSR::CSR_MEDELEG, RXVCSR::CSR_MIDELEG:
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

endmodule
