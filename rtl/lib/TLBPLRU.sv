// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

module TLBPLRU #(
    parameter width = 4
) (
    input  logic                clk,
    input  logic                reset,
    input  logic [way_bits-1:0] access_way,
    input  logic                valid,
    output logic [way_bits-1:0] lru_out
);

    localparam way_bits = $clog2(width);

    logic [width-1:0] new_plru;
    wire  [width-1:0] new_plru_reg;

    RXVDFF #(
        .width(width)
    ) new_plru_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (new_plru),
        .q    (new_plru_reg)
    );

    always_comb begin
        new_plru = new_plru_reg;
        if (valid) begin
            new_plru[access_way] = 1'b1;
            if (&new_plru) begin
                new_plru             = 'b0;
                new_plru[access_way] = 1'b1;
            end
        end
    end

    always_comb begin
        integer i;
        lru_out = 'b0;
        for (i = 0; i < width; i = i + 1) begin : lru_lookup
            if (!new_plru_reg[i]) begin
                lru_out = way_bits'(i);
            end
        end
    end

endmodule
