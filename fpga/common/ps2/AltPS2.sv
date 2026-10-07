// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// PS/2 port with the register interface of the Altera University Program
// PS/2 core so that it binds to the upstream "altr,ps2-1.0" driver:
//
//   0x0 data:    read  [31:16] RAVAIL, the bytes available including this
//                      one, [15] RVALID, [7:0] data, popped by the read.
//                write [7:0] byte to send.
//   0x4 control: [0] RE receive interrupt enable, [8] RI receive interrupt
//                pending, [10] CE command error.
//
// The driver drains the FIFO while RAVAIL is non-zero so it must count the
// byte returned by the read.  Received bytes with a parity error are
// dropped.  A byte written while one is being sent is held until the
// current one completes.
module AltPS2 #(
    parameter int clk_freq   = 60000000,
    parameter int fifo_order = 4
) (
    input  logic        clk,
    input  logic        reset,
    output logic        irq,
    // Register interface (AXILiteRegs)
    // verilator lint_off UNUSEDSIGNAL
    input  logic        reg_wr,
    input  logic [15:0] reg_waddr,
    input  logic [31:0] reg_wdata,
    input  logic [ 3:0] reg_wstrb,
    input  logic        reg_rd,
    input  logic [15:0] reg_raddr,
    // verilator lint_on UNUSEDSIGNAL
    output logic [31:0] reg_rdata,
    // Connector
    input  logic        ps2_clk_i,
    output logic        ps2_clk_low,
    input  logic        ps2_dat_i,
    output logic        ps2_dat_low
);

    localparam int depth = 1 << fifo_order;

    logic [           7:0] rx;
    logic                  rx_valid;
    logic                  rx_error;
    logic                  start_tx;
    logic [           7:0] tx;
    logic                  tx_busy;
    // verilator lint_off UNUSEDSIGNAL
    logic                  tx_complete;
    // verilator lint_on UNUSEDSIGNAL
    logic                  tx_pending;
    logic [           7:0] tx_pending_data;

    logic [           7:0] fifo          [depth];
    logic [fifo_order:0]   wr_ptr;
    logic [fifo_order:0]   rd_ptr;
    logic [fifo_order:0]   count;
    logic                  rx_push;
    logic                  rx_pop;
    logic                  rx_irq_en;
    logic [           7:0] head;

    PS2Host #(
        .clk_freq(clk_freq)
    ) host (
        .clk        (clk),
        .reset      (reset),
        .rx         (rx),
        .rx_valid   (rx_valid),
        .error      (rx_error),
        .start_tx   (start_tx),
        .tx         (tx),
        .tx_busy    (tx_busy),
        .tx_complete(tx_complete),
        .ps2_clk_i  (ps2_clk_i),
        .ps2_clk_low(ps2_clk_low),
        .ps2_dat_i  (ps2_dat_i),
        .ps2_dat_low(ps2_dat_low)
    );

    always_comb begin
        count     = wr_ptr - rd_ptr;
        head      = fifo[rd_ptr[fifo_order-1:0]];
        // A full FIFO drops new bytes.
        rx_push   = rx_valid && !rx_error && count != (fifo_order + 1)'(depth);
        rx_pop    = reg_rd && reg_raddr[2] == 1'b0 && count != '0;
        irq       = rx_irq_en && count != '0;

        start_tx  = tx_pending && !tx_busy;
        tx        = tx_pending_data;

        reg_rdata = '0;
        if (reg_raddr[2] == 1'b0) begin
            reg_rdata[31:16] = 16'(count);
            reg_rdata[15]    = count != '0;
            reg_rdata[7:0]   = count != '0 ? head : 8'h00;
        end else begin
            reg_rdata[0] = rx_irq_en;
            reg_rdata[8] = irq;
        end
    end

    always_ff @(posedge clk) begin
        if (rx_push) begin
            fifo[wr_ptr[fifo_order-1:0]] <= rx;
            wr_ptr                       <= wr_ptr + 1'b1;
        end
        if (rx_pop) rd_ptr <= rd_ptr + 1'b1;

        if (start_tx) tx_pending <= 1'b0;

        if (reg_wr && reg_waddr[2] == 1'b0 && reg_wstrb[0]) begin
            tx_pending      <= 1'b1;
            tx_pending_data <= reg_wdata[7:0];
        end

        if (reg_wr && reg_waddr[2] == 1'b1 && reg_wstrb[0]) rx_irq_en <= reg_wdata[0];

        if (reset) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            tx_pending <= 1'b0;
            rx_irq_en  <= 1'b0;
        end
    end

endmodule
