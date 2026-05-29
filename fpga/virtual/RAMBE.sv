// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"
module RAMBE #(
    parameter depth      = 32,
    parameter byte_width = 4
) (
    input  logic                  clk,
    input  logic [ addr_bits-1:0] addr,
    input  logic                  wren,
    input  logic [ data_bits-1:0] din,
    input  logic [byte_width-1:0] byte_en,
    output logic [ data_bits-1:0] dout
);

    localparam addr_bits = $clog2(depth);
    localparam data_bits = 8 * byte_width;

    altsyncram #(
        .byte_size                    (8),
        .numwords_a                   (depth),
        .width_a                      (byte_width * 8),
        .width_byteen_a               (byte_width),
        .widthad_a                    ($clog2(depth)),
        .operation_mode               ("SINGLE_PORT"),
        .outdata_aclr_a               ("NONE"),
        .outdata_reg_a                ("UNREGISTERED"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ")
    ) ram (
        .clock0        (clk),
        .clocken0      (1'b1),
        .address_a     (addr),
        .data_a        (din),
        .wren_a        (wren),
        .q_a           (dout),
        .aclr0         (1'b0),
        .rden_a        (1'b1),
        .aclr1         (1'b0),
        .address_b     (1'b1),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_b     (1'b1),
        .clock1        (1'b1),
        .clocken1      (1'b1),
        .clocken2      (1'b1),
        .clocken3      (1'b1),
        .data_b        (1'b1),
        .eccstatus     (),
        .q_b           (),
        .rden_b        (1'b1),
        .wren_b        (1'b0)
    );

endmodule
