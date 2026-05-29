// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

module PosedgeDetect (
    input  logic clk,
    input  logic reset,
    input  logic d,
    output logic q
);

    logic last_val;

    always_comb begin
        q = d & ~last_val;
    end

    RXVDFF last_val_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (d),
        .q    (last_val)
    );

endmodule
