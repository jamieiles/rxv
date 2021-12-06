`default_nettype none

import RXVCSR::RXVCSR_id;

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

    logic [31:0] rd_data_next;
    logic [31:0] mscratch;
    logic        mscratch_wren;

    always_comb begin
        unique case (rd_addr)
            RXVCSR::CSR_MVENDORID: rd_data_next = vendorid;
            RXVCSR::CSR_MARCHID: rd_data_next = archid;
            RXVCSR::CSR_MIMPID: rd_data_next = impid;
            RXVCSR::CSR_MSCRATCH: rd_data_next = mscratch;
            default: rd_data_next = 32'b0;
        endcase
    end

    always_comb begin
        mscratch_wren = wr_en && wr_addr == RXVCSR::CSR_MSCRATCH;
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

endmodule
