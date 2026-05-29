// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_uop;
import RXVTypes::commit_width;

module RXVDivExec (
    input  logic                           clk,
    input  logic                           reset,
    input  logic                           kill_valid,
    input  logic                           exec_valid,
    input  logic                           exec_have_writeback,
    input  phys_reg_tag                    exec_rd,
    input  logic        [commit_width-1:0] exec_id,
    input  logic        [            31:0] op1,
    input  logic        [            31:0] op2,
    output phys_reg_tag                    exec_reg_addr,
    output logic                           exec_reg_wr_en,
    output logic        [            31:0] exec_reg_wr_data,
    output logic                           exec_complete,
    output logic        [commit_width-1:0] exec_complete_id,
    input  rxv_uop                         exec_uop,
    output logic                           busy
);

    logic        is_signed;
    logic [31:0] dividend;
    logic [31:0] divisor;
    logic [31:0] quotient;
    logic [31:0] remainder;
    logic        valid;
    logic        complete;
    logic        result_is_quotient_next;
    logic        result_is_quotient;
    logic        busy_next;
    logic        have_writeback_next;
    logic        have_writeback;

    RXVDiv RXVDiv (
        .clk      (clk),
        .reset    (reset),
        .valid    (valid),
        .is_signed(is_signed),
        .dividend (dividend),
        .divisor  (divisor),
        .quotient (quotient),
        .remainder(remainder)
    );

    always_comb begin
        busy_next = busy;
        if (complete) busy_next = 1'b0;
        if (valid) busy_next = 1'b1;
    end

    always_comb begin
        have_writeback_next = exec_valid & ~kill_valid & exec_have_writeback;
    end

    always_comb begin
        valid    = exec_valid & ~kill_valid;
        dividend = op1;
        divisor  = op2;

        unique case (exec_uop)
            RXVTypes::UOP_DIV, RXVTypes::UOP_REM: is_signed = 1'b1;
            RXVTypes::UOP_DIVU, RXVTypes::UOP_REMU: is_signed = 1'b0;
            default: is_signed = 1'b0;
        endcase

        unique case (exec_uop)
            RXVTypes::UOP_DIV, RXVTypes::UOP_DIVU: result_is_quotient_next = 1'b1;
            default: result_is_quotient_next = 1'b0;
        endcase

        exec_reg_wr_data = result_is_quotient ? quotient : remainder;
        exec_reg_wr_en   = complete & have_writeback;
        exec_complete    = complete;
    end

    RXVDFF #(
        .width(commit_width)
    ) exec_complete_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (valid),
        .d    (exec_id),
        .q    (exec_complete_id)
    );

    RXVDFF #(
        .width($bits(phys_reg_tag))
    ) exec_reg_addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (valid),
        .d    (exec_rd),
        .q    (exec_reg_addr)
    );

    RXVDFF result_is_quotient_dff (
        .clk  (clk),
        .reset(reset),
        .en   (valid),
        .d    (result_is_quotient_next),
        .q    (result_is_quotient)
    );

    RXVDFFPipe #(
        .stages(33)
    ) complete_pipe (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (valid),
        .q    (complete)
    );

    RXVDFF busy_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (busy_next),
        .q    (busy)
    );

    RXVDFF have_writeback_dff (
        .clk  (clk),
        .reset(reset),
        .en   (valid),
        .d    (have_writeback_next),
        .q    (have_writeback)
    );

endmodule
