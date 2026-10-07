// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// A console for boards without a serial port: enough of an ns16550a for
// OpenSBI's uart8250 driver and the Linux 8250 driver and earlycon, with
// the transmitted bytes kept in a ring buffer that the board reads out by
// other means (JTAG on the DE0-CV).
//
// Registers are 32-bit apart (reg-shift 2).  The transmitter is always
// empty, nothing is ever received and there are no interrupts so Linux
// polls.  The divisor, line control, modem control and scratch registers
// read back what was written so the drivers' probing is satisfied.
//
// The buffer is read 8 bytes at a time: read_data is the 8 bytes at
// read_addr * 8 a cycle later, byte n is at byte_count - 1 modulo the
// buffer size.
module ConsoleUART #(
    parameter int buf_order = 13
) (
    input  logic                     clk,
    input  logic                     reset,
    // Register interface (AXILiteRegs)
    // verilator lint_off UNUSEDSIGNAL
    input  logic                     reg_wr,
    input  logic [             15:0] reg_waddr,
    input  logic [             31:0] reg_wdata,
    input  logic [              3:0] reg_wstrb,
    input  logic                     reg_rd,
    input  logic [             15:0] reg_raddr,
    // verilator lint_on UNUSEDSIGNAL
    output logic [             31:0] reg_rdata,
    // Buffer read out
    input  logic [buf_order-4:0]     read_addr,
    output logic [             63:0] read_data,
    output logic [             31:0] byte_count
);

    localparam int lines = 1 << (buf_order - 3);

    logic [7:0] ier;
    logic [7:0] lcr;
    logic [7:0] mcr;
    logic [7:0] scr;
    logic [7:0] dll;
    logic [7:0] dlm;
    logic       dlab;
    logic       tx;

    // One RAM per byte lane so that a single byte can be written and eight
    // read at once.
    logic [7:0] lane[8][lines];

    assign dlab = lcr[7];
    assign tx   = reg_wr && reg_waddr[4:2] == 3'd0 && !dlab && reg_wstrb[0];

    always_comb begin
        unique case (reg_raddr[4:2])
            3'd0:    reg_rdata = dlab ? 32'(dll) : 32'h0;
            3'd1:    reg_rdata = dlab ? 32'(dlm) : 32'(ier);
            // FIFOs enabled, no interrupt pending
            3'd2:    reg_rdata = 32'hc1;
            3'd3:    reg_rdata = 32'(lcr);
            3'd4:    reg_rdata = 32'(mcr);
            // Transmitter empty
            3'd5:    reg_rdata = 32'h60;
            // DCD, DSR and CTS
            3'd6:    reg_rdata = 32'hb0;
            default: reg_rdata = 32'(scr);
        endcase
    end

    always_ff @(posedge clk) begin
        if (reg_wr && reg_wstrb[0]) begin
            unique case (reg_waddr[4:2])
                3'd0: if (dlab) dll <= reg_wdata[7:0];
                3'd1: if (dlab) dlm <= reg_wdata[7:0]; else ier <= reg_wdata[7:0];
                3'd3: lcr <= reg_wdata[7:0];
                3'd4: mcr <= reg_wdata[7:0];
                3'd7: scr <= reg_wdata[7:0];
                default: ;
            endcase
        end

        if (tx) byte_count <= byte_count + 1'b1;

        if (reset) begin
            ier        <= '0;
            lcr        <= '0;
            mcr        <= '0;
            scr        <= '0;
            dll        <= '0;
            dlm        <= '0;
            byte_count <= '0;
        end
    end

    genvar l;
    generate
        for (l = 0; l < 8; ++l) begin : gen_lane
            always_ff @(posedge clk) begin
                if (tx && byte_count[2:0] == 3'(l))
                    lane[l][byte_count[buf_order-1:3]] <= reg_wdata[7:0];
                read_data[l*8+:8] <= lane[l][read_addr];
            end
        end
    endgenerate

endmodule
