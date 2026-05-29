// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"
module DPRAM #(
    parameter depth = 32,
    parameter width = 8
) (
    `POWER_PIN_PORTS
    input  logic                 clk,
    // verilator lint_off UNUSED
    input  logic                 reset,
    // verilator lint_on UNUSED
    // Port A
    input  logic [addr_bits-1:0] addr_a,
    output logic [    width-1:0] dout_a,
    // Port B
    input  logic [addr_bits-1:0] addr_b,
    input  logic                 wren_b,
    input  logic [    width-1:0] din_b
);

    localparam addr_bits = $clog2(depth);

    logic [width-1:0] mem[0:depth-1];

    always_ff @(posedge clk) begin
        if (wren_b) begin
            mem[addr_b] <= din_b;
        end
    end

    always_ff @(posedge clk) begin
        dout_a <= mem[addr_a];
    end

    integer i;
    initial begin
        for (i = 0; i < depth; i = i + 1) mem[i] = width'(1'b0);
    end

    `include "DPRAM_formal.sv"

endmodule
