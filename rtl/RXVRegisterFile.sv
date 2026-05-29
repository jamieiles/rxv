// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVTypes::phys_reg_tag;
import RXVTypes::num_phys_regs;

module RXVRegisterFile #(
    parameter int banked = 0
) (
    input  logic               clk,
    // verilator lint_off UNUSED
    input  logic               reset,
    // verilator lint_on UNUSED
    input  phys_reg_tag        rd_addr_a,
    output logic        [31:0] rd_data_a,
    input  phys_reg_tag        rd_addr_b,
    output logic        [31:0] rd_data_b,
    input  logic               wr_en,
    input  phys_reg_tag        wr_addr,
    input  logic        [31:0] wr_data
);

    generate
        if (banked == 0) begin : DFF
            RXVRegisterFileDFF RXVRegisterFileDFF (
                .clk      (clk),
                .reset    (reset),
                .rd_addr_a(rd_addr_a),
                .rd_data_a(rd_data_a),
                .rd_addr_b(rd_addr_b),
                .rd_data_b(rd_data_b),
                .wr_en    (wr_en),
                .wr_addr  (wr_addr),
                .wr_data  (wr_data)
            );
        end else begin : RAM
            RXVRegisterFileBanked RXVRegisterFileBanked (
                .clk      (clk),
                .rd_addr_a(rd_addr_a),
                .rd_data_a(rd_data_a),
                .rd_addr_b(rd_addr_b),
                .rd_data_b(rd_data_b),
                .wr_en    (wr_en),
                .wr_addr  (wr_addr),
                .wr_data  (wr_data)
            );
        end
    endgenerate

endmodule
