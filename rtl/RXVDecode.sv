`default_nettype none

module RXVDecode(
    input logic clk,
    input logic reset,
    input logic [31:0] fd_pc,
    input logic fd_valid,
    input logic w_exception,
    input logic e_instr_ac,
    input logic m_abort,
    input logic fd_intr,
    input logic [31:0] instruction,
    input logic [31:0] mscratch_reg,
    input logic [31:0] mcause_reg,
    input logic [31:0] mtval_reg,
    input logic [31:0] mtvec_reg,
    input logic [31:0] mip_reg,
    input logic [31:0] mie_reg,
    input logic [31:0] mcounteren_reg,
    input logic [31:0] mstatus_reg,
    input logic [31:0] mepc_reg,
    input logic [63:0] mcycle_reg,
    input logic [63:0] minstret_reg,
    output logic [31:0] de_csr_val,
    output logic [31:0] de_immed,
    output logic [31:0] de_pc,
    output logic [31:0] de_next_seq_pc,
    output logic [31:0] de_branch_tgt,
    output logic [4:0] de_rd,
    output logic de_writeback,
    output logic de_illegal_instr,
    output logic [31:0] de_instruction,
    output logic de_valid,
    output logic [1:0] de_br_type,
    output logic [2:0] de_funct3,
    output logic de_load,
    output logic de_store,
    output logic [1:0] de_ls_width,
    output logic de_load_sext,
`ifdef RXV_RVFI
    output logic de_read_csr,
    output logic de_intr,
`endif
    output logic de_write_csr,
    output logic [4:0] de_csr_immed,
    output logic de_do_mret,
    output logic de_do_ecall,
    output logic de_do_ebreak,
    output logic de_do_fence,
    output logic [3:0] de_alu_op,
    output logic de_op2_immed,
    output logic d_write_pc,
    output logic [31:0] d_br_tgt,
    output logic df_flush,
    // Forward from end of exec stage back to start of exec?
    output logic fwd_rs1_e,
    output logic fwd_rs2_e,
    output logic [4:0] rs1,
    output logic [4:0] rs2,
    output logic d_load_delay
);

`include "RiscVDefines.svh"

// Instruction field extraction
wire [6:0] funct7       = instruction[31:25];
assign rs2              = instruction[24:20];
assign rs1              = instruction[19:15];
wire [2:0] funct3       = instruction[14:12];
wire [4:0] d_rd         = instruction[11:7];
wire [6:0] d_opcode     = instruction[6:0];

// Instruction decode
wire [31:0] i_immed     = {20'b0, instruction[31:20]};
wire [31:0] i_immed_s   = {{20{i_immed[11]}}, i_immed[11:0]};
wire [31:0] s_immed     = {{21{instruction[31]}}, instruction[30:25], instruction[11:7]};
wire [31:0] b_immed     = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
wire [31:0] u_immed     = {instruction[31:12], 12'b0};
wire [31:0] j_immed     = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};

assign df_flush         = d_fence |
                          d_write_csr |
                          d_read_mepc |
                          d_illegal_instr |
                          (instruction == INSTR_ECALL) |
                          (instruction == INSTR_EBREAK);
wire d_read_csr         = d_opcode == OPC_ENV &&
                          ((funct3 == CSRRW && |d_rd) ||
                           (funct3 == CSRRS || funct3 == CSRRC) ||
                           (funct3 == CSRRWI && |d_rd) ||
                           (funct3 == CSRRSI || funct3 == CSRRCI));

wire d_write_csr        = d_opcode == OPC_ENV &&
                          ((funct3 == CSRRW || funct3 == CSRRWI) ||
                           ((funct3 == CSRRS || funct3 == CSRRC) && |d_rd) ||
                           ((funct3 == CSRRSI || funct3 == CSRRCI) && |rs1));

wire [31:0] d_immed     = d_opcode == OPC_LUI ? u_immed :
                          d_opcode == OPC_AUIPC ? fd_pc + u_immed :
                          d_opcode == OPC_JAL ? j_immed :
                          d_opcode == OPC_JALR ? i_immed_s :
                          d_opcode == OPC_LOAD ? i_immed_s :
                          d_opcode == OPC_ARITHI ? i_immed_s :
                          d_opcode == OPC_BRANCH ? b_immed :
                          d_opcode == OPC_STORE ? s_immed :
                          d_opcode == OPC_ENV ? i_immed : i_immed;
assign d_br_tgt         = d_opcode == OPC_JAL ? fd_pc + j_immed :
                          d_opcode == OPC_JALR ? fd_pc + i_immed_s :
                          fd_pc + b_immed;

wire d_writeback        = d_opcode == OPC_LUI ||
                          d_opcode == OPC_AUIPC ||
                          d_opcode == OPC_JAL ||
                          d_opcode == OPC_JALR ||
                          d_opcode == OPC_LOAD ||
                          d_opcode == OPC_ARITHI ||
                          d_opcode == OPC_ARITH ||
                          d_read_csr;

wire d_bad_opc          = !(d_opcode == OPC_LUI ||
                            d_opcode == OPC_AUIPC ||
                            d_opcode == OPC_JAL ||
                            d_opcode == OPC_JALR ||
                            d_opcode == OPC_BRANCH ||
                            d_opcode == OPC_LOAD ||
                            d_opcode == OPC_STORE ||
                            d_opcode == OPC_ARITHI ||
                            d_opcode == OPC_ARITH ||
                            d_opcode == OPC_FENCE ||
                            d_opcode == OPC_ENV);
wire d_is_branch        = d_opcode == OPC_JAL ||
                          d_opcode == OPC_JALR ||
                          d_opcode == OPC_BRANCH;
wire d_bad_jalr         = d_opcode == OPC_JALR &&
                          funct3 != 3'b000;
wire d_bad_branch       = d_opcode == OPC_BRANCH &&
                          (funct3 == 3'd2 || funct3 == 3'd3);
wire d_bad_load         = d_opcode == OPC_LOAD &&
                          (funct3 == 3'd3 || funct3 == 3'd6 || funct3 == 3'd7);
wire d_bad_store        = d_opcode == OPC_STORE &&
                          !(funct3 == 3'd0 || funct3 == 3'd1 || funct3 == 3'd2);
wire d_bad_arithi       = d_opcode == OPC_ARITHI &&
                          ((funct3 == 3'd1 && funct7 != 7'd0) ||
                           (funct3 == 3'd5 && |{funct7[6], funct7[4:0]}));
wire d_bad_arith        = d_opcode == OPC_ARITH &&
                          (((funct3 == 3'd0 || funct3 == 3'd5) && |{funct7[6], funct7[4:0]}) ||
                           ((funct3 != 3'd0 && funct3 != 3'd5) && |funct7));
                           // FIXME: check supported CSRs
wire d_bad_csr          = i_immed > 32'h1000;
wire d_is_csr_access    = d_opcode == OPC_ENV && !(funct3 == 3'd0 || funct3 == 3'd4);
wire d_bad_env          = d_opcode == OPC_ENV &&
                          (funct3 == 3'd4 ||
                           (funct3 == 3'd0 &&
                            !(instruction == INSTR_ECALL ||
                             instruction == INSTR_EBREAK ||
                             instruction == INSTR_MRET   ||
                             instruction == INSTR_WFI))) ||
                          d_is_csr_access && d_bad_csr;
wire d_illegal_instr    = d_bad_opc | d_bad_branch | d_bad_load | d_bad_store |
                          d_bad_arithi | d_bad_arith | d_bad_env | d_bad_jalr | d_bad_fence;
wire [1:0] d_br_type    = d_opcode == OPC_JAL ? BRANCH_IMMED :
                          d_opcode == OPC_JALR ? BRANCH_INDIR :
                          d_opcode == OPC_BRANCH ? BRANCH_COND : BRANCH_NONE;
wire [1:0] d_ls_width   = funct3[1:0];
wire d_load_sext        = ~funct3[2];
wire d_read_mepc        = instruction == INSTR_MRET;
// verilator lint_off UNUSED
wire [3:0] d_fence_fm   = instruction[31:28];
// verilator lint_on UNUSED
wire d_fence            = d_opcode == OPC_FENCE && !d_bad_fence;
wire d_bad_fence        = d_opcode == OPC_FENCE &&
                          !(funct3[2:1] == 2'b0 && d_fence_fm[2:0] == 3'b0);
assign d_load_delay     = (d_opcode == OPC_LOAD || (d_is_branch && d_br_type != BRANCH_IMMED)) && !d_illegal_instr;
wire [3:0] d_alu_op     = d_opcode == OPC_ARITH && funct3 == 3'd0 && ~funct7[5] ? ALU_OP_ADD :
                          d_opcode == OPC_ARITH && funct3 == 3'd0 &&  funct7[5] ? ALU_OP_SUB :
                          d_opcode == OPC_ARITHI && funct3 == 3'd0 ? ALU_OP_ADD :
                          d_opcode == OPC_LUI ? ALU_OP_IMMED :
                          d_opcode == OPC_AUIPC ? ALU_OP_IMMED :
                          d_opcode == OPC_JAL ? ALU_OP_NPC :
                          d_opcode == OPC_JALR ? ALU_OP_NPC :
                          d_opcode == OPC_STORE ? ALU_OP_ADD :
                          d_opcode == OPC_LOAD ? ALU_OP_ADD :
                          d_opcode == OPC_ENV && d_read_csr ? ALU_OP_RDCSR :
                          d_read_mepc ? ALU_OP_RDCSR :
                          funct3 == 3'd1 ? ALU_OP_SLL :
                          funct3 == 3'd2 ? ALU_OP_LT :
                          funct3 == 3'd3 ? ALU_OP_LTU :
                          funct3 == 3'd4 ? ALU_OP_XOR :
                          funct3 == 3'd5 && ~funct7[5] ? ALU_OP_SRL :
                          funct3 == 3'd5 &&  funct7[5] ? ALU_OP_SRA :
                          funct3 == 3'd6 ? ALU_OP_OR :
                          funct3 == 3'd7 ? ALU_OP_AND : ALU_OP_AND;
wire d_op2_immed        = d_opcode == OPC_ARITHI ||
                          (d_is_branch && d_br_type == BRANCH_INDIR) ||
                          d_opcode == OPC_STORE ||
                          d_opcode == OPC_LOAD;
wire abort              = e_instr_ac |
                          w_exception |
                          w_exception |
                          m_abort;
wire valid              = fd_valid && !abort && !d_illegal_instr;
wire [31:0] d_csr_val   = d_immed[15:0] == CSR_MARCHID ? RXV_MARCHID :
                          d_immed[15:0] == CSR_MSCRATCH ? mscratch_reg :
                          d_immed[15:0] == CSR_MCAUSE ? mcause_reg :
                          d_immed[15:0] == CSR_MTVAL ? mtval_reg :
                          d_immed[15:0] == CSR_MTVEC ? mtvec_reg :
                          d_immed[15:0] == CSR_MIP ? mip_reg :
                          d_immed[15:0] == CSR_MIE ? mie_reg :
                          d_immed[15:0] == CSR_MCOUNTEREN ? mcounteren_reg :
                          d_immed[15:0] == CSR_MSTATUS ? mstatus_reg :
                          d_immed[15:0] == CSR_MEPC || d_read_mepc ? mepc_reg :
                          d_immed[15:0] == CSR_MCYCLE ? mcycle_reg[31:0] :
                          d_immed[15:0] == CSR_MCYCLEH ? mcycle_reg[63:32] :
                          d_immed[15:0] == CSR_MINSTRET ? minstret_reg[31:0] :
                          d_immed[15:0] == CSR_MINSTRETH ? minstret_reg[63:32] :
                          32'h00000000;

assign d_write_pc       = fd_valid && d_is_branch && d_br_type == BRANCH_IMMED;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        de_immed <= 32'b0;
        de_writeback <= 1'b0;
        de_instruction <= 32'h00000013;
        de_rd <= 5'b0;
        de_pc <= 32'b0;
        de_next_seq_pc <= 32'b0;
        de_branch_tgt <= 32'b0;
        de_illegal_instr <= 1'b0;
        de_valid <= 1'b0;
        de_br_type <= 2'b0;
        de_funct3 <= 3'b0;
        de_load <= 1'b0;
        de_store <= 1'b0;
        de_ls_width <= 2'b0;
        de_load_sext <= 1'b0;
`ifdef RXV_RVFI
        de_read_csr <= 1'b0;
        de_intr <= 1'b0;
`endif
        de_write_csr <= 1'b0;
        de_csr_immed <= 5'b0;
        de_do_mret <= 1'b0;
        de_do_ecall <= 1'b0;
        de_do_ebreak <= 1'b0;
        de_do_fence <= 1'b0;
        de_alu_op <= 4'b0;
        de_op2_immed <= 1'b0;
        de_csr_val <= 32'b0;
        fwd_rs1_e <= 1'b0;
        fwd_rs2_e <= 1'b0;
    end else begin
        de_immed <= d_immed;
        de_writeback <= d_writeback;
        de_instruction <= instruction;
        de_rd <= d_rd;
        de_pc <= fd_pc;
        de_next_seq_pc <= fd_pc + 32'd4;
        de_branch_tgt <= d_br_tgt;
        de_illegal_instr <= fd_valid && !abort && d_illegal_instr;
        de_valid <= valid;
        de_br_type <= valid ? d_br_type : 2'b00;
        de_funct3 <= funct3;
        de_load <= d_opcode == OPC_LOAD;
        de_store <= d_opcode == OPC_STORE;
        de_ls_width <= d_ls_width;
        de_load_sext <= d_load_sext;
`ifdef RXV_RVFI
        de_read_csr <= d_read_csr;
        de_intr <= fd_intr;
`endif
        de_write_csr <= fd_valid && d_write_csr;
        de_csr_immed <= rs1;
        de_do_mret <= valid && d_read_mepc;
        de_do_ecall <= valid && instruction == INSTR_ECALL;
        de_do_ebreak <= valid && instruction == INSTR_EBREAK;
        de_do_fence <= valid && d_fence;
        de_alu_op <= d_alu_op;
        de_op2_immed <= d_op2_immed;
        de_csr_val <= d_csr_val;

        fwd_rs1_e <= |de_rd && de_valid && de_writeback && de_rd == rs1;
        fwd_rs2_e <= |de_rd && de_valid && de_writeback && de_rd == rs2;
    end
end

endmodule
