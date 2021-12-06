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

module RXVCSRFile #(
    parameter logic [31:0] vendorid = 0,
    parameter logic [31:0] archid   = 0,
    parameter logic [31:0] impid    = 0
) (
    input  logic        clk,
    input  logic        reset,
    // Read port
    input  logic [11:0] rd_addr,
    output logic [31:0] rd_data,
    // Write port
    input  logic [11:0] wr_addr,
    input  logic [31:0] wr_data,
    input  logic        wr_en
);

    logic   [31:0] rd_data_next;
    logic   [31:0] mscratch;
    logic          mscratch_wren;

    mstatus        mstatus_reg;
    logic          mstatus_wren;
    mtvec          mtvec_reg;
    logic          mtvec_wren;
    mepc           mepc_reg;
    logic          mepc_wren;
    mcause         mcause_reg;
    logic          mcause_wren;
    mtval          mtval_reg;
    logic          mtval_wren;

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
            default: rd_data_next = 32'b0;
        endcase
    end

    always_comb begin
        mscratch_wren = wr_en && wr_addr == RXVCSR::CSR_MSCRATCH;
        mstatus_wren  = wr_en && wr_addr == RXVCSR::CSR_MSTATUS;
        mtvec_wren    = wr_en && wr_addr == RXVCSR::CSR_MTVEC;
        mepc_wren     = wr_en && wr_addr == RXVCSR::CSR_MEPC;
        mcause_wren   = wr_en && wr_addr == RXVCSR::CSR_MCAUSE;
        mtval_wren    = wr_en && wr_addr == RXVCSR::CSR_MTVAL;
    end

`ifdef verilator
    always_ff @(posedge clk) if (wr_addr[11:10] == 2'b11) assert (!wr_en);
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
        .d    (pack_mstatus(wr_data)),
        .q    (mstatus_reg)
    );

    RXVDFF #(
        .width($bits(mtvec_reg))
    ) mtvec_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mtvec_wren),
        .d    (pack_mtvec(wr_data)),
        .q    (mtvec_reg)
    );

    RXVDFF #(
        .width($bits(mepc_reg))
    ) mepc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mepc_wren),
        .d    (pack_mepc(wr_data)),
        .q    (mepc_reg)
    );

    RXVDFF #(
        .width($bits(mcause_reg))
    ) mcause_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mcause_wren),
        .d    (pack_mcause(wr_data)),
        .q    (mcause_reg)
    );

    RXVDFF #(
        .width($bits(mtval_reg))
    ) mtval_dff (
        .clk  (clk),
        .reset(reset),
        .en   (mtval_wren),
        .d    (pack_mtval(wr_data)),
        .q    (mtval_reg)
    );

endmodule
