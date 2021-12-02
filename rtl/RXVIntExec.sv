`default_nettype none

import RXVTypes::rxv_alu_op;
import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_prediction;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_uop;

module RXVIntExec #(
    parameter int commit_order = 3
) (
    input  logic                             clk,
    input  logic                             reset,
    input  logic                             exec_valid,
    input  rxv_alu_op                        exec_alu_op,
    input  logic                             exec_have_writeback,
    input  phys_reg_tag                      exec_rd,
    input  logic          [commit_width-1:0] exec_id,
    input  logic          [            31:0] op1,
    input  logic          [            31:0] op2,
    output phys_reg_tag                      exec_reg_addr,
    output logic                             exec_reg_wr_en,
    output logic          [            31:0] exec_reg_wr_data,
    output logic                             exec_complete,
    output logic          [commit_width-1:0] exec_complete_id,
    input  logic          [            31:0] exec_immed,
    input  rxv_opcode                        exec_opcode,
    input  logic          [            31:1] exec_branch_target,
    input  rxv_uop                           exec_uop,
    // Prediction
    input  logic          [            31:2] exec_pc,
    input  logic          [            31:2] exec_next_pc,
    input  rxv_prediction                    exec_prediction,
    // Branching + prediction
    output logic                             exec_predict_update,
    output logic          [             1:0] exec_predict_prev_strength,
    output logic                             exec_update_predict_taken,
    output logic          [            31:2] exec_update_predict_address,
    output logic          [            31:2] exec_update_predict_target,
    output logic                             exec_resteer,
    output logic          [            31:2] exec_resteer_tgt
);

    always_comb begin
        exec_predict_update         = 'b0;
        exec_predict_prev_strength  = 'b0;
        exec_update_predict_taken   = 'b0;
        exec_update_predict_address = 'b0;
        exec_update_predict_target  = 'b0;
        exec_resteer                = 'b0;
        exec_resteer_tgt            = 'b0;
    end

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic [31:0] alu_q;
    logic [31:0] alu_op2;
    logic        zero;
    logic        alu_op2_immed;

    always_comb begin
        alu_op2_immed = exec_opcode == RXVTypes::OPC_IMM;
    end

    always_comb begin
        alu_op2 = alu_op2_immed ? exec_immed : op2;
    end

    RXVALU RXVALU (
        .a   (op1),
        .b   (alu_op2),
        .op  (exec_alu_op),
        .q   (alu_q),
        .zero(zero)
    );

    RXVDFF #(
        .width($bits(phys_reg_tag))
    ) exec_reg_addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_rd),
        .q    (exec_reg_addr)
    );

    RXVDFF #(
        .width(32)
    ) exec_wr_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (alu_q),
        .q    (exec_reg_wr_data)
    );

    RXVDFF #(
        .width(commit_width)
    ) exec_complete_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_id),
        .q    (exec_complete_id)
    );

    RXVDFF exec_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_valid),
        .q    (exec_complete)
    );

    RXVDFF exec_reg_wr_en_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_valid & exec_have_writeback),
        .q    (exec_reg_wr_en)
    );

`ifdef FORMAL
    always_comb
        if (exec_alu_op == RXVTypes::ALU_SLT) assert ($signed(op1) < $signed(alu_op2) == alu_q[0]);
    always_comb if (exec_alu_op == RXVTypes::ALU_SLTU) assert (op1 < alu_op2 == alu_q[0]);
`endif

endmodule
