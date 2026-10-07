// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// Boot ROM: a dual port RAM with an instruction port and a data port.  The
// boot ROM is cacheable so both see cache line bursts and the data port
// writes back dirty lines (.data is in the ROM).  Each port streams a word
// per cycle; the RAM address is advanced as a beat is accepted so the next
// word is ready on the following cycle.
module BootROM #(
    parameter int    size_bytes = 32768,
    parameter        init_file  = ""
) (
    input  logic                    clk,
    input  logic                    reset,
           MemInterface.Subordinate ibus,
           MemInterface.Subordinate dbus
);

    localparam int depth = size_bytes / 4;
    localparam int addr_bits = $clog2(depth);

    logic [3:0][7:0] mem[depth];

    logic [addr_bits-1:0] i_addr;
    logic [         31:0] i_q;
    logic [addr_bits-1:0] d_addr;
    logic                 d_we;
    logic [          3:0] d_be;
    logic [         31:0] d_wdata;
    logic [         31:0] d_q;

    initial begin
        if (init_file != "") $readmemh(init_file, mem);
    end

    always_ff @(posedge clk) begin
        i_q <= mem[i_addr];
    end

    always_ff @(posedge clk) begin
        // Quartus only infers a RAM with the byte lanes written out.
        if (d_we) begin
            if (d_be[0]) mem[d_addr][0] <= d_wdata[7:0];
            if (d_be[1]) mem[d_addr][1] <= d_wdata[15:8];
            if (d_be[2]) mem[d_addr][2] <= d_wdata[23:16];
            if (d_be[3]) mem[d_addr][3] <= d_wdata[31:24];
        end
        d_q <= mem[d_addr];
    end

    BootROMPort #(
        .addr_bits(addr_bits)
    ) i_port (
        .clk     (clk),
        .reset   (reset),
        .bus     (ibus),
        .ram_addr(i_addr),
        // verilator lint_off PINCONNECTEMPTY
        .ram_we  (),
        .ram_be  (),
        .ram_wdata(),
        // verilator lint_on PINCONNECTEMPTY
        .ram_q   (i_q)
    );

    BootROMPort #(
        .addr_bits(addr_bits)
    ) d_port (
        .clk      (clk),
        .reset    (reset),
        .bus      (dbus),
        .ram_addr (d_addr),
        .ram_we   (d_we),
        .ram_be   (d_be),
        .ram_wdata(d_wdata),
        .ram_q    (d_q)
    );

endmodule
