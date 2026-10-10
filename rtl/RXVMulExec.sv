// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_uop;
import RXVTypes::commit_width;

module RXVMulExec (
    input  logic                           clk,
    input  logic                           reset,
    input  logic                           kill_valid,
    input  logic                           exec_valid,
    input  phys_reg_tag                    exec_rd,
    input  logic                           exec_have_writeback,
    input  logic        [commit_width-1:0] exec_id,
    input  logic        [            31:0] op1,
    input  logic        [            31:0] op2,
    output phys_reg_tag                    exec_reg_addr,
    output logic                           exec_reg_wr_en,
    output logic        [            31:0] exec_reg_wr_data,
    // The result that will be in exec_reg_wr_data next cycle
    output logic                           mul_fwd_valid,
    output phys_reg_tag                    mul_fwd_rd,
    output logic                           exec_complete,
    output logic        [commit_width-1:0] exec_complete_id,
    input  rxv_uop                         exec_uop
);

    typedef struct packed {
        logic valid;
        logic high;
        phys_reg_tag addr;
        logic [commit_width-1:0] complete_id;
        logic have_writeback;
    } mul_op;

    mul_op                          mul_op_in;
    mul_op                          mul_op_out;
    mul_op                          mul_op_mid;
    mul_op                          mul_op_mid_high;
    mul_op                          mul_op_sel;
    logic        [            31:0] result_lo_early;
    // verilator lint_off UNUSED
    logic        [            63:0] result;
    // verilator lint_on UNUSED
    logic        [            31:0] exec_reg_wr_data_next;
    phys_reg_tag                    exec_reg_addr_next;
    logic                           exec_reg_wr_en_next;
    logic                           exec_complete_next;
    logic        [commit_width-1:0] exec_complete_id_next;
    logic                           signed_a;
    logic                           signed_b;

    RXVMul RXVMul (
        .clk     (clk),
        .reset   (reset),
        .signed_a(signed_a),
        .a       (op1),
        .signed_b(signed_b),
        .b       (op2),
        .q       (result),
        .q_lo_early(result_lo_early)
    );

    always_comb begin
        mul_op_in.valid          = exec_valid & ~kill_valid;
        mul_op_in.addr           = exec_rd;
        mul_op_in.complete_id    = exec_id;
        mul_op_in.high           = exec_uop != RXVTypes::UOP_MUL;
        mul_op_in.have_writeback = exec_valid & ~kill_valid & exec_have_writeback;

        unique case (exec_uop)
            RXVTypes::UOP_MUL, RXVTypes::UOP_MULH: begin
                signed_a = 1'b1;
                signed_b = 1'b1;
            end
            RXVTypes::UOP_MULHSU: begin
                signed_a = 1'b1;
                signed_b = 1'b0;
            end
            RXVTypes::UOP_MULHU: begin
                signed_a = 1'b0;
                signed_b = 1'b0;
            end
            default: begin
                signed_a = 1'b1;
                signed_b = 1'b1;
            end
        endcase
    end

    // MUL completes after 3 stages, the high word ops after 4: the scheduler
    // prevents both completing in the same cycle.
    always_comb begin
        mul_op_sel = mul_op_mid.valid && !mul_op_mid.high ? mul_op_mid : mul_op_out;
        mul_op_mid_high = mul_op_mid;
        if (!mul_op_mid.high) mul_op_mid_high = 'b0;
    end

    always_comb begin
        mul_fwd_valid = mul_op_sel.have_writeback;
        mul_fwd_rd    = mul_op_sel.addr;
    end

    always_comb begin
        exec_reg_addr_next    = mul_op_sel.addr;
        exec_reg_wr_en_next   = mul_op_sel.have_writeback;
        exec_reg_wr_data_next = !mul_op_sel.high ? result_lo_early : result[63:32];
        exec_complete_next    = mul_op_sel.valid;
        exec_complete_id_next = mul_op_sel.complete_id;
    end

    RXVDFFPipe #(
        .stages(3),
        .width ($bits(mul_op))
    ) mul_op_pipe (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (mul_op_in),
        .q    (mul_op_mid)
    );

    RXVDFF #(
        .width($bits(mul_op))
    ) mul_op_out_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (mul_op_mid_high),
        .q    (mul_op_out)
    );

    RXVAssert no_mul_complete_collision (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(mul_op_mid.valid && !mul_op_mid.high && mul_op_out.valid))
    );

    RXVDFF #(
        .width(32)
    ) mul_reg_wr_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_reg_wr_data_next),
        .q    (exec_reg_wr_data)
    );

    RXVDFF #(
        .width($bits(phys_reg_tag))
    ) mul_reg_addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_reg_addr_next),
        .q    (exec_reg_addr)
    );

    RXVDFF #(
        .width(commit_width)
    ) mul_complete_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_complete_id_next),
        .q    (exec_complete_id)
    );

    RXVDFF mul_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_complete_next),
        .q    (exec_complete)
    );

    RXVDFF mul_reg_wr_en_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_reg_wr_en_next),
        .q    (exec_reg_wr_en)
    );

endmodule
