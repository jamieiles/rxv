`default_nettype none

module RXVExec(
    input logic clk,
    input logic reset,
    output logic e_write_pc,
    output logic [31:0] e_next_pc,
    output logic em_writeback,
    output logic [4:0] em_rd,
    output logic [31:0] em_result,
    output logic [31:0] em_pc,
    output logic [31:0] em_next_pc,
    output logic [31:0] em_instruction,
    output logic [31:0] em_store_data,
    output logic em_illegal_instr,
    output logic em_valid,
    output logic em_load,
    output logic em_store,
    output logic [1:0] em_ls_width,
    output logic [15:0] em_csr_rd,
    output logic em_load_sext,
    output logic em_write_csr,
    output logic [31:0] em_csr_wdata,
    output logic em_instr_align_check,
    output logic em_do_ecall,
    output logic em_do_ebreak,
    output logic em_do_fence,
    output logic em_do_mret,
    output logic e_instr_ac,
    output logic fwd_rs1_m,
    output logic fwd_rs2_m,
    input logic [31:0] de_csr_val,
    input logic [3:0] de_alu_op,
    input logic [31:0] de_immed,
    input logic [31:0] de_next_seq_pc,
    input logic [1:0] de_br_type,
    input logic [31:0] de_branch_tgt,
    input logic [2:0] de_funct3,
    input logic de_op2_immed,
    input logic de_do_mret,
    input logic [4:0] de_csr_immed,
    input logic de_valid,
    input logic [4:0] de_rd,
    input logic [31:0] de_pc,
    input logic [31:0] de_instruction,
    input logic de_illegal_instr,
    input logic de_load,
    input logic de_store,
    input logic [1:0] de_ls_width,
    input logic de_load_sext,
    input logic de_write_csr,
    input logic de_do_ecall,
    input logic de_do_ebreak,
    input logic de_do_fence,
    input logic de_writeback,
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input logic [31:0] rs1_data,
    input logic [31:0] rs2_data,
    input logic w_exception,
`ifdef RXV_RVFI
    input logic de_intr,
    output logic em_intr,
`endif
    input logic m_abort
);

`include "RiscVDefines.svh"

// Instruction execution
wire [31:0] alu_out     = de_alu_op == ALU_OP_IMMED ? de_immed :
                          de_alu_op == ALU_OP_NPC ? de_next_seq_pc :
                          de_alu_op == ALU_OP_RDCSR ? de_csr_val :
                          de_alu_op == ALU_OP_ADD ? e_add :
                          de_alu_op == ALU_OP_SUB ? e_sub :
                          de_alu_op == ALU_OP_SLL ? e_sll :
                          de_alu_op == ALU_OP_LT ? e_lt :
                          de_alu_op == ALU_OP_LTU ? e_ltu :
                          de_alu_op == ALU_OP_XOR ? e_xor :
                          de_alu_op == ALU_OP_SRL ? e_srl :
                          de_alu_op == ALU_OP_SRA ? e_sra :
                          de_alu_op == ALU_OP_OR ? e_or :
                          de_alu_op == ALU_OP_AND ? e_and : e_and;
wire [31:0] e_branch_tgt= de_br_type == BRANCH_INDIR ? {e_add[31:1], 1'b0} :
                          e_br_taken ? de_branch_tgt : de_next_seq_pc;

wire e_br_taken         = de_funct3 == BR_BEQ  ? rs1_data == rs2_data :
                          de_funct3 == BR_BNE  ? rs1_data != rs2_data :
                          de_funct3 == BR_BLT  ? $signed(rs1_data) < $signed(rs2_data) :
                          de_funct3 == BR_BGE  ? $signed(rs1_data) >= $signed(rs2_data) :
                          de_funct3 == BR_BLTU ? rs1_data < rs2_data :
                          /*de_funct3 == BR_BGEU*/ rs1_data >= rs2_data;
wire [31:0] e_arith_op2 = de_op2_immed ? de_immed : rs2_data;
wire [4:0] e_shift_cnt  = e_arith_op2[4:0];
wire [31:0] e_sll       = rs1_data << e_shift_cnt;
wire [31:0] e_srl       = rs1_data >> e_shift_cnt;
wire [31:0] e_sra       = $signed(rs1_data) >>> e_shift_cnt;
wire [31:0] e_add       = rs1_data + e_arith_op2;
wire [31:0] e_sub       = rs1_data - e_arith_op2;
wire [31:0] e_xor       = rs1_data ^ e_arith_op2;
wire [31:0] e_or        = rs1_data | e_arith_op2;
wire [31:0] e_and       = rs1_data & e_arith_op2;
wire [31:0] e_lt        = {31'b0, $signed(rs1_data) < $signed(e_arith_op2)};
wire [31:0] e_ltu       = {31'b0, rs1_data < e_arith_op2};

wire [31:0] e_csr_wdata = de_funct3 == CSRRW ? rs1_data :
                          de_funct3 == CSRRS ? de_csr_val | rs1_data :
                          de_funct3 == CSRRC ? de_csr_val & ~rs1_data :
                          de_funct3 == CSRRWI ? {27'b0, de_csr_immed} :
                          de_funct3 == CSRRSI ? de_csr_val | {27'b0, de_csr_immed} :
                          de_funct3 == CSRRCI ? de_csr_val & ~{27'b0, de_csr_immed} :
                          rs1_data;
assign e_instr_ac       = de_valid &&
                          de_br_type != BRANCH_NONE && e_next_pc[1];
assign e_next_pc        = de_br_type == BRANCH_NONE ? de_next_seq_pc :
                          de_br_type == BRANCH_IMMED ? de_branch_tgt :
                          e_branch_tgt;
assign e_write_pc       = de_br_type == BRANCH_INDIR ||
                          de_br_type == BRANCH_COND;


always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        em_writeback <= 1'b0;
        em_rd <= 5'b0;
        em_result <= 32'b0;
        em_pc <= 32'b0;
        em_next_pc <= 32'b0;
        em_instruction <= 32'b0;
        em_illegal_instr <= 1'b0;
        em_valid <= 1'b0;
        em_store_data <= 32'b0;
        em_load <= 1'b0;
        em_store <= 1'b0;
        em_ls_width <= 2'b0;
        em_load_sext <= 1'b0;
        em_write_csr <= 1'b0;
        em_csr_rd <= 16'b0;
        em_csr_wdata <= 32'b0;
        em_instr_align_check <= 1'b0;
        em_do_ecall <= 1'b0;
        em_do_ebreak <= 1'b0;
        em_do_fence <= 1'b0;
        em_do_mret <= 1'b0;
        fwd_rs1_m <= 1'b0;
        fwd_rs2_m <= 1'b0;
`ifdef RXV_RVFI
        em_intr <= 1'b0;
`endif
    end else begin
        em_writeback <= de_valid && de_writeback && !e_instr_ac && !w_exception;
        em_rd <= de_rd;
        em_result <= alu_out;
        em_pc <= de_pc;
        em_next_pc <= e_next_pc;
        em_instruction <= de_instruction;
        em_illegal_instr <= de_illegal_instr && !w_exception;
        em_valid <= de_valid && !m_abort && !w_exception;
        em_store_data <= rs2_data;
        em_load <= de_load;
        em_store <= de_store;
        em_ls_width <= de_ls_width;
        em_load_sext <= de_load_sext;
        em_write_csr <= de_write_csr;
        em_csr_rd <= de_immed[15:0];
        em_csr_wdata <= e_csr_wdata;
        em_instr_align_check <= e_instr_ac && !w_exception;
        em_do_ecall <= de_do_ecall && !w_exception;
        em_do_ebreak <= de_do_ebreak && !w_exception;
        em_do_fence <= de_do_fence && !w_exception;
        em_do_mret <= de_do_mret && !w_exception;
`ifdef RXV_RVFI
        em_intr <= de_intr;
`endif

        fwd_rs1_m <= |em_rd && em_valid && em_writeback && em_rd == rs1;
        fwd_rs2_m <= |em_rd && em_valid && em_writeback && em_rd == rs2;
    end
end

endmodule
