// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"
module SyncPulse (
    input  logic clk,
    input  logic reset,
    input  logic d,
    output logic p,
    output logic q
);

    logic synced;
    logic last_val;

    assign p = synced ^ last_val;
    assign q = last_val;

    RXVDFF last_val_reg (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (synced),
        .q    (last_val)
    );

    BitSync BitSync (
        .clk  (clk),
        .reset(reset),
        .d    (d),
        .q    (synced)
    );

endmodule
