`include "RXV.svh"

import RXVTypes::rxv_alu_op;
import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_prediction;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_uop;
import RXVTypes::commit_width;
import RXVCSR::RXVException;
import RXVCSR::privilege_t;

module RXVIntExec (
    input  logic                             clk,
    input  logic                             reset,
    input  logic                             kill_valid,
    input  logic                             exec_valid,
    input  rxv_alu_op                        exec_alu_op,
    input  rxv_csr_op                        exec_csr_op,
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
    input  logic          [            31:0] exec_csr_rd_data,
    output logic          [            11:0] exec_csr_wr_addr,
    output logic          [            31:0] exec_csr_wr_data,
    output logic                             exec_csr_wr_en,
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
    output logic          [            31:2] exec_resteer_tgt,
    // Exception return
    input  logic          [            31:2] mepc_in,
    input  logic          [            31:2] sepc_in,
    output logic                             do_mret,
    output logic                             do_sret,
    // Exception handling
    input  RXVException                      decode_exception,
    input  logic          [commit_width-1:0] decode_except_id,
    // Exception handling
    output RXVException                      exec_exception,
    output logic          [commit_width-1:0] exec_except_id,
    input  privilege_t                       current_privilege
);

    logic                           valid;
    logic        [            31:0] alu_q;
    logic        [            31:0] alu_op2;
    logic                           zero;
    logic                           alu_op2_immed;
    logic                           branch_taken;
    logic                           branch_mispredict;
    logic                           is_branch;

    logic        [            31:0] csr_q;
    logic        [            31:0] csr_alu_op2;
    logic        [             4:0] csr_immed_val;
    logic        [            11:0] csr_addr;

    logic                           exec_predict_update_next;
    logic        [             1:0] exec_predict_prev_strength_next;
    logic                           exec_update_predict_taken_next;
    logic        [            31:2] exec_update_predict_address_next;
    logic        [            31:2] exec_update_predict_target_next;
    logic                           exec_resteer_next;
    logic        [            31:2] exec_resteer_tgt_next;
    logic        [            31:0] exec_reg_wr_data_next;
    logic                           is_mret;
    logic                           is_sret;
    // verilator lint_off UNUSED
    logic        [            31:0] branch_target;
    logic        [            31:0] jalr_target;
    // verilator lint_on UNUSED
    logic                           unconditional_branch;
    logic                           branch_misalign;

    logic        [            11:0] exec_csr_wr_addr_next;
    logic        [            31:0] exec_csr_wr_data_next;
    logic                           exec_csr_wr_en_next;

    RXVException                    exec_exception_next;
    logic        [commit_width-1:0] exec_except_id_next;
    logic                           do_mret_next;
    logic                           do_sret_next;

    RXVALU RXVALU (
        .a   (op1),
        .b   (alu_op2),
        .op  (exec_alu_op),
        .q   (alu_q),
        .zero(zero)
    );

    RXVCSRALU RXVCSRALU (
        .old_val(exec_csr_rd_data),
        .new_val(csr_alu_op2),
        .op     (exec_csr_op),
        .q      (csr_q)
    );

    function logic [3:0] ecall_type;
        case (current_privilege)
            RXVCSR::PRIV_M: ecall_type = RXVCSR::CAUSE_M_ECALL;
            RXVCSR::PRIV_S: ecall_type = RXVCSR::CAUSE_S_ECALL;
            RXVCSR::PRIV_U: ecall_type = RXVCSR::CAUSE_U_ECALL;
            default: ecall_type = RXVCSR::CAUSE_U_ECALL;
        endcase
    endfunction

    always_comb begin
        alu_op2_immed = exec_opcode == RXVTypes::OPC_IMM;
    end

    always_comb begin
        alu_op2 = alu_op2_immed ? exec_immed : op2;
    end

    always_comb begin
        csr_alu_op2 = exec_uop == RXVTypes::UOP_CSRI ? {27'b0, csr_immed_val} : op1;
    end

    always_comb begin
        valid = exec_valid & ~kill_valid;
    end

    always_comb begin
        csr_immed_val = exec_immed[19:15];
        csr_addr      = exec_immed[31:20];
    end

    always_comb begin
        jalr_target = op1 + exec_immed;
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_ALU: exec_reg_wr_data_next = alu_q;
            RXVTypes::UOP_JAL, RXVTypes::UOP_JALR: exec_reg_wr_data_next = {exec_next_pc, 2'b0};
            RXVTypes::UOP_LUI: exec_reg_wr_data_next = exec_immed;
            RXVTypes::UOP_AUIPC: exec_reg_wr_data_next = exec_immed + {exec_pc, 2'b0};
            RXVTypes::UOP_CSR, RXVTypes::UOP_CSRI: exec_reg_wr_data_next = exec_csr_rd_data;
            default: exec_reg_wr_data_next = 32'b0;
        endcase
    end

    always_comb begin
        unconditional_branch = exec_uop == RXVTypes::UOP_JAL || exec_uop == RXVTypes::UOP_JALR;
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_BEQ: branch_taken = zero;
            RXVTypes::UOP_BNE: branch_taken = ~zero;
            RXVTypes::UOP_BLT: branch_taken = alu_q[0];
            RXVTypes::UOP_BGE: branch_taken = ~alu_q[0];
            RXVTypes::UOP_JAL: branch_taken = 1'b1;
            RXVTypes::UOP_JALR: branch_taken = 1'b1;
            default: branch_taken = 1'b0;
        endcase
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_BEQ, RXVTypes::UOP_BNE, RXVTypes::UOP_BLT,
            RXVTypes::UOP_BGE, RXVTypes::UOP_JAL, RXVTypes::UOP_JALR:
            is_branch = 1'b1;
            default: is_branch = 1'b0;
        endcase
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_JALR: branch_target = {jalr_target[31:1], 1'b0};
            RXVTypes::UOP_MRET: branch_target = {mepc_in, 2'b0};
            RXVTypes::UOP_SRET: branch_target = {sepc_in, 2'b0};
            default: branch_target = {exec_branch_target, 1'b0};
        endcase
    end

    always_comb begin
        branch_misalign = is_branch && branch_taken && |branch_target[1:0];
    end

    always_comb begin
        is_mret = exec_uop == RXVTypes::UOP_MRET;
        is_sret = exec_uop == RXVTypes::UOP_SRET;
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
        exec_predict_update_next = valid && is_branch && !branch_misalign;
        exec_predict_prev_strength_next  = unconditional_branch ? 2'b01 : exec_prediction.predict_strength;
        exec_update_predict_taken_next = branch_taken;
        exec_update_predict_address_next = exec_pc;
        exec_update_predict_target_next = branch_target[31:2];
        exec_resteer_next = valid && (branch_mispredict || is_mret || is_sret || exec_csr_wr_en_next) && !branch_misalign;
        exec_resteer_tgt_next = branch_taken || is_mret || is_sret ? branch_target[31:2] : exec_next_pc;
    end

    always_comb begin
        do_mret_next = valid && exec_uop == RXVTypes::UOP_MRET && !exec_exception_next.valid;
        do_sret_next = valid && exec_uop == RXVTypes::UOP_SRET && !exec_exception_next.valid;
    end

    always_comb begin
        exec_csr_wr_addr_next = csr_addr;
        exec_csr_wr_data_next = csr_q;
        exec_csr_wr_en_next = |csr_addr && valid &&
            (exec_uop == RXVTypes::UOP_CSR || exec_uop == RXVTypes::UOP_CSRI) &&
            exec_csr_op != RXVTypes::CSR_READ;
    end

    always_comb begin
        exec_exception_next = decode_exception;
        exec_except_id_next = decode_except_id;

        if (kill_valid || exec_resteer) exec_exception_next.valid = 1'b0;

        if (valid && branch_misalign) begin
            exec_exception_next.pc    = exec_pc;
            exec_exception_next.val   = branch_target;
            exec_exception_next.cause = RXVCSR::CAUSE_INSTR_MISALIGN;
            exec_exception_next.valid = 1'b1;
            exec_exception_next.irq   = 1'b0;
        end

        if (valid && exec_uop == RXVTypes::UOP_ECALL) begin
            exec_exception_next.pc    = exec_pc;
            exec_exception_next.val   = {exec_pc, 2'b0};
            exec_exception_next.cause = ecall_type();
            exec_exception_next.valid = 1'b1;
            exec_exception_next.irq   = 1'b0;
        end

        if (valid && exec_uop == RXVTypes::UOP_EBREAK) begin
            exec_exception_next.pc    = exec_pc;
            exec_exception_next.val   = {exec_pc, 2'b0};
            exec_exception_next.cause = RXVCSR::CAUSE_BREAKPOINT;
            exec_exception_next.valid = 1'b1;
            exec_exception_next.irq   = 1'b0;
        end
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

    RXVDFF #(
        .width(12)
    ) exec_csr_wr_addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_csr_wr_addr_next),
        .q    (exec_csr_wr_addr)
    );

    RXVDFF #(
        .width(32)
    ) exec_csr_wr_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_csr_wr_data_next),
        .q    (exec_csr_wr_data)
    );

    RXVDFF exec_csr_wr_en_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_csr_wr_en_next),
        .q    (exec_csr_wr_en)
    );

    RXVDFF #(
        .width($bits(RXVCSR::RXVException))
    ) exec_exception_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_exception_next),
        .q    (exec_exception)
    );

    RXVDFF #(
        .width($bits(exec_except_id))
    ) exec_except_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_except_id_next),
        .q    (exec_except_id)
    );

    RXVDFF do_mret_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (do_mret_next),
        .q    (do_mret)
    );

    RXVDFF do_sret_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (do_sret_next),
        .q    (do_sret)
    );

`ifdef FORMAL
    always_comb
        if (exec_alu_op == RXVTypes::ALU_SLT) assert ($signed(op1) < $signed(alu_op2) == alu_q[0]);
    always_comb if (exec_alu_op == RXVTypes::ALU_SLTU) assert (op1 < alu_op2 == alu_q[0]);
`endif

endmodule
