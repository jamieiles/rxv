// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVTypes::phys_reg_tag;
import RXVTypes::num_phys_regs;

module RXVRegisterFileBanked (
    input  logic               clk,
    input  phys_reg_tag        rd_addr_a,
    output logic        [31:0] rd_data_a,
    input  phys_reg_tag        rd_addr_b,
    output logic        [31:0] rd_data_b,
    input  logic               wr_en,
    input  phys_reg_tag        wr_addr,
    input  logic        [31:0] wr_data
);

    logic [31:0] bank_a       [0:num_phys_regs-1];
    logic [31:0] bank_b       [0:num_phys_regs-1];

    logic        wr_en_masked;

    always_comb begin
        wr_en_masked = wr_en & |wr_addr;
    end

    // verilator lint_off BLKSEQ
    //
    // Infer a true dual port RAM with read-during-write returning the new
    // data.
    always_ff @(posedge clk) begin
        if (wr_en_masked) bank_a[wr_addr] = wr_data;
        rd_data_a = bank_a[rd_addr_a];
    end

    always_ff @(posedge clk) begin
        if (wr_en_masked) bank_b[wr_addr] = wr_data;
        rd_data_b = bank_b[rd_addr_b];
    end
    // verilator lint_on BLKSEQ

`ifdef RXV_TRACE
    function logic [31:0] read_reg;
        input phys_reg_tag r;

        read_reg = bank_a[r];
    endfunction
`endif

endmodule
