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
    input  logic                             kill_valid,

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

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic        valid;
    logic [31:0] alu_q;
    logic [31:0] alu_op2;
    logic        zero;
    logic        alu_op2_immed;
    logic        branch_taken;
    logic        branch_mispredict;

    logic        exec_predict_update_next;
    logic [ 1:0] exec_predict_prev_strength_next;
    logic        exec_update_predict_taken_next;
    logic [31:2] exec_update_predict_address_next;
    logic [31:2] exec_update_predict_target_next;
    logic        exec_resteer_next;
    logic [31:2] exec_resteer_tgt_next;
    logic [31:0] exec_reg_wr_data_next;

    always_comb begin
        alu_op2_immed = exec_opcode == RXVTypes::OPC_IMM;
    end

    always_comb begin
        alu_op2 = alu_op2_immed ? exec_immed : op2;
    end

    always_comb begin
        valid = exec_valid & ~kill_valid;
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_ALU: exec_reg_wr_data_next = alu_q;
            RXVTypes::UOP_JAL: exec_reg_wr_data_next = {exec_next_pc, 2'b0};
            default: exec_reg_wr_data_next = 32'b0;
        endcase

    end

    RXVALU RXVALU (
        .a   (op1),
        .b   (alu_op2),
        .op  (exec_alu_op),
        .q   (alu_q),
        .zero(zero)
    );

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_BEQ: branch_taken = zero;
            RXVTypes::UOP_BNE: branch_taken = ~zero;
            RXVTypes::UOP_BLT: branch_taken = alu_q[0];
            RXVTypes::UOP_BGE: branch_taken = ~alu_q[0];
            RXVTypes::UOP_JAL: branch_taken = 1'b1;
            default: branch_taken = 1'b0;
        endcase
    end

    always_comb begin
        branch_mispredict = 1'b0;
        if (branch_taken && !exec_prediction.predicted) branch_mispredict = 1'b1;
        if (exec_prediction.predicted && exec_prediction.predict_taken != branch_taken)
            branch_mispredict = 1'b1;
        if (exec_prediction.predicted && exec_prediction.prediction != exec_branch_target[31:2])
            branch_mispredict = 1'b1;
    end

    always_comb begin
        exec_predict_update_next         = valid && branch_taken;
        exec_predict_prev_strength_next  = exec_prediction.predict_strength;
        exec_update_predict_taken_next   = branch_taken;
        exec_update_predict_address_next = exec_pc;
        exec_update_predict_target_next  = exec_branch_target[31:2];
        exec_resteer_next                = valid && branch_mispredict;
        exec_resteer_tgt_next            = branch_taken ? exec_branch_target[31:2] : exec_next_pc;
    end

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
        .d    (exec_reg_wr_data_next),
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
        .d    (valid),
        .q    (exec_complete)
    );

    RXVDFF exec_reg_wr_en_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (valid & exec_have_writeback),
        .q    (exec_reg_wr_en)
    );

    RXVDFF exec_predict_update_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_predict_update_next),
        .q    (exec_predict_update)
    );

    RXVDFF #(
        .width(2)
    ) exec_predict_prev_strength_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_predict_prev_strength_next),
        .q    (exec_predict_prev_strength)
    );

    RXVDFF exec_update_predict_taken_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_update_predict_taken_next),
        .q    (exec_update_predict_taken)
    );

    RXVDFF #(
        .width(30)
    ) exec_update_predict_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_update_predict_address_next),
        .q    (exec_update_predict_address)
    );

    RXVDFF #(
        .width(30)
    ) exec_update_predict_target_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_update_predict_target_next),
        .q    (exec_update_predict_target)
    );

    RXVDFF exec_resteer_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_resteer_next),
        .q    (exec_resteer)
    );

    RXVDFF #(
        .width(30)
    ) exec_resteer_tgt_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_resteer_tgt_next),
        .q    (exec_resteer_tgt)
    );

`ifdef FORMAL
    always_comb
        if (exec_alu_op == RXVTypes::ALU_SLT) assert ($signed(op1) < $signed(alu_op2) == alu_q[0]);
    always_comb if (exec_alu_op == RXVTypes::ALU_SLTU) assert (op1 < alu_op2 == alu_q[0]);
`endif

endmodule
