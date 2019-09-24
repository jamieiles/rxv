`ifdef verilator
`define RXV_RVFI
`endif

module RXVCore(input logic clk,
               input logic reset,
               // Interrupts
               input logic intr_timer,
               input logic intr_ext,
               // Instruction bus
               output logic [31:0] i_addr,
               input logic [31:0] i_data,
               // Data bus
               output logic d_access,
               output logic d_wren,
               output logic [31:0] d_addr,
               output logic [3:0] d_bytesel,
               output logic [31:0] d_wdata,
               input logic [31:0] d_rdata
`ifdef RXV_RVFI
               ,
               // RVFI
               output logic rvfi_valid,
               output logic [63:0] rvfi_order,
               output logic rvfi_trap,
               output logic rvfi_halt,
               output logic rvfi_intr,
               output logic [1:0] rvfi_mode,
               output logic [1:0] rvfi_ixl,
               output logic [4:0] rvfi_rs1_addr,
               output logic [4:0] rvfi_rs2_addr,
               output logic [31:0] rvfi_rs1_rdata,
               output logic [31:0] rvfi_rs2_rdata,
               output logic [31:0] rvfi_insn,
               output logic [4:0] rvfi_rd_addr,
               output logic [31:0] rvfi_rd_wdata,
               output logic [31:0] rvfi_pc_rdata,
               output logic [31:0] rvfi_pc_wdata,
               output logic [31:0] rvfi_csr_marchid_wmask,
               output logic [31:0] rvfi_csr_marchid_rdata,
               output logic [31:0] rvfi_csr_marchid_rmask,
               output logic [31:0] rvfi_csr_marchid_wdata,
               output logic [31:0] rvfi_csr_mcause_wmask,
               output logic [31:0] rvfi_csr_mcause_rdata,
               output logic [31:0] rvfi_csr_mcause_rmask,
               output logic [31:0] rvfi_csr_mcause_wdata,
               output logic [31:0] rvfi_csr_mtvec_wmask,
               output logic [31:0] rvfi_csr_mtvec_rdata,
               output logic [31:0] rvfi_csr_mtvec_rmask,
               output logic [31:0] rvfi_csr_mtvec_wdata,
               output logic [31:0] rvfi_csr_mepc_wmask,
               output logic [31:0] rvfi_csr_mepc_rdata,
               output logic [31:0] rvfi_csr_mepc_rmask,
               output logic [31:0] rvfi_csr_mepc_wdata,
               output logic [31:0] rvfi_csr_mtval_wmask,
               output logic [31:0] rvfi_csr_mtval_rdata,
               output logic [31:0] rvfi_csr_mtval_rmask,
               output logic [31:0] rvfi_csr_mtval_wdata,
               output logic [31:0] rvfi_csr_mscratch_wmask,
               output logic [31:0] rvfi_csr_mscratch_rdata,
               output logic [31:0] rvfi_csr_mscratch_rmask,
               output logic [31:0] rvfi_csr_mscratch_wdata,
               output logic [31:0] rvfi_csr_mip_wmask,
               output logic [31:0] rvfi_csr_mip_rdata,
               output logic [31:0] rvfi_csr_mip_rmask,
               output logic [31:0] rvfi_csr_mip_wdata,
               output logic [31:0] rvfi_csr_mie_wmask,
               output logic [31:0] rvfi_csr_mie_rdata,
               output logic [31:0] rvfi_csr_mie_rmask,
               output logic [31:0] rvfi_csr_mie_wdata,
               output logic [31:0] rvfi_csr_mstatus_wmask,
               output logic [31:0] rvfi_csr_mstatus_rdata,
               output logic [31:0] rvfi_csr_mstatus_rmask,
               output logic [31:0] rvfi_csr_mstatus_wdata,
               output logic [31:0] rvfi_mem_addr,
               output logic [3:0] rvfi_mem_rmask,
               output logic [3:0] rvfi_mem_wmask,
               output logic [31:0] rvfi_mem_rdata,
               output logic [31:0] rvfi_mem_wdata
`endif // RXV_RVFI
               );

reg [31:0] reset_vector = 32'b0;

// Instruction fetch
// verilator lint_off BLKANDNBLK
reg [31:0] pc;
// verilator lint_on BLKANDNBLK
reg delay_slot;
wire f_insert_nop       = flush_pipeline | delay_slot;
wire [31:0] instruction = f_insert_nop || 1'b0 ? 32'h00000013 : i_data;
wire d_write_pc         = fd_valid && d_is_branch && d_br_type == BRANCH_IMMED;
wire [31:0] next_pc     = w_write_pc ? w_next_pc :
                          e_write_pc ? e_next_pc :
                          d_write_pc ? d_br_tgt :
                          d_load_delay || f_flush_pipeline || (flush_pipeline && !f_finish_flush) ? pc : pc + 32'd4;
assign i_addr           = next_pc;
reg flush_pipeline;

wire f_finish_flush     = (mw_valid & mw_write_csr) |
                          (mw_valid & mw_do_fence) |
                          (mw_valid & mw_do_mret) |
                          w_exception;
wire f_flush_pipeline   = (d_fence |
                           d_write_csr |
                           d_read_mepc |
			   d_illegal_instr |
			   m_abort |
                           (instruction == INSTR_ECALL) |
                           (instruction == INSTR_EBREAK)) & fd_valid & ~w_exception;

// Instruction field extraction
wire [6:0] funct7       = instruction[31:25];
wire [4:0] rs2          = instruction[24:20];
wire [4:0] rs1          = instruction[19:15];
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

localparam OPC_LUI      = 7'b011_0111,
           OPC_AUIPC    = 7'b001_0111,
           OPC_JAL      = 7'b110_1111,
           OPC_JALR     = 7'b110_0111,
           OPC_BRANCH   = 7'b110_0011,
           OPC_LOAD     = 7'b000_0011,
           OPC_STORE    = 7'b010_0011,
           OPC_ARITHI   = 7'b001_0011,
           OPC_ARITH    = 7'b011_0011,
           OPC_FENCE    = 7'b000_1111,
           OPC_ENV      = 7'b111_0011;

localparam ALU_OP_ADD   = 4'd0,
           ALU_OP_SUB   = 4'd1,
           ALU_OP_SLL   = 4'd2,
           ALU_OP_LT    = 4'd3,
           ALU_OP_LTU   = 4'd4,
           ALU_OP_XOR   = 4'd5,
           ALU_OP_SRL   = 4'd6,
           ALU_OP_SRA   = 4'd7,
           ALU_OP_OR    = 4'd8,
           ALU_OP_AND   = 4'd9,
           ALU_OP_IMMED = 4'd10,
           ALU_OP_NPC   = 4'd11,
           ALU_OP_RDCSR = 4'd12;

localparam BR_BEQ       = 3'b000,
           BR_BNE       = 3'b001,
           BR_BLT       = 3'b100,
           BR_BGE       = 3'b101,
           BR_BLTU      = 3'b110,
           BR_BGEU      = 3'b111;

localparam INSTR_ECALL  = 32'h00000073,
           INSTR_EBREAK = 32'h00100073,
           INSTR_MRET   = 32'h30200073,
	   INSTR_WFI	= 32'h10500073;

localparam BRANCH_NONE  = 2'b00,
           BRANCH_IMMED = 2'b01,
           BRANCH_INDIR = 2'b10,
           BRANCH_COND  = 2'b11;

localparam LS_WIDTH_8   = 2'b00,
           LS_WIDTH_16  = 2'b01,
           LS_WIDTH_32  = 2'b10;

localparam CSRRW        = 3'b001,
           CSRRS        = 3'b010,
           CSRRC        = 3'b011,
           CSRRWI       = 3'b101,
           CSRRSI       = 3'b110,
           CSRRCI       = 3'b111;

localparam CSR_MVENDORID    = 16'h0f11,
           CSR_MARCHID      = 16'h0f12,
           CSR_MIMPID       = 16'h0f13,
           CSR_MHARTID      = 16'h0f14,
           CSR_MSTATUS      = 16'h0300,
           CSR_MISA         = 16'h0301,
           CSR_MIE          = 16'h0304,
           CSR_MTVEC        = 16'h0305,
           CSR_MCOUNTEREN   = 16'h0306,
           CSR_MSCRATCH     = 16'h0340,
           CSR_MEPC         = 16'h0341,
           CSR_MCAUSE       = 16'h0342,
           CSR_MTVAL        = 16'h0343,
           CSR_MIP          = 16'h0344,
           CSR_MCYCLE       = 16'h0b00,
           CSR_MCYCLEH      = 16'h0b80,
           CSR_MINSTRET     = 16'h0b02,
           CSR_MINSTRETH    = 16'h0b82;

localparam EX_INSTR_ALIGN   = 4'd0,
           EX_INSTR_ACCESS  = 4'd1,
           EX_ILLEGAL_INSTR = 4'd2,
           EX_BREAKPOINT    = 4'd3,
           EX_LOAD_ALIGN    = 4'd4,
           EX_LOAD_ACCESS   = 4'd5,
           EX_STORE_ALIGN   = 4'd6,
           EX_STORE_ACCESS  = 4'd7,
           EX_ECALL_U       = 4'd8,
           EX_ECALL_S       = 4'd9,
           EX_ECALL_M       = 4'd11,
           EX_INSTR_PF      = 4'd12,
           EX_LOAD_PF       = 4'd13,
           EX_STORE_PF      = 4'd15;

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
wire [31:0] d_br_tgt    = d_opcode == OPC_JAL ? fd_pc + j_immed :
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
wire d_load_delay       = (d_opcode == OPC_LOAD || (d_is_branch && d_br_type != BRANCH_IMMED)) && !d_illegal_instr;
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

// Instruction execution
wire [31:0] alu_out     = de_alu_op == ALU_OP_IMMED ? de_immed :
                          de_alu_op == ALU_OP_NPC ? de_next_seq_pc :
                          de_alu_op == ALU_OP_RDCSR ? e_csr_val :
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

wire e_write_pc         = de_br_type == BRANCH_INDIR ||
                          de_br_type == BRANCH_COND;
wire e_br_taken         = de_funct3 == BR_BEQ  ? rs1_fwd == rs2_fwd :
                          de_funct3 == BR_BNE  ? rs1_fwd != rs2_fwd :
                          de_funct3 == BR_BLT  ? $signed(rs1_fwd) < $signed(rs2_fwd) :
                          de_funct3 == BR_BGE  ? $signed(rs1_fwd) >= $signed(rs2_fwd) :
                          de_funct3 == BR_BLTU ? rs1_fwd < rs2_fwd :
                          /*de_funct3 == BR_BGEU*/ rs1_fwd >= rs2_fwd;
wire [31:0] e_arith_op2 = de_op2_immed ? de_immed : rs2_fwd;
wire [4:0] e_shift_cnt  = e_arith_op2[4:0];
wire [31:0] e_sll       = rs1_fwd << e_shift_cnt;
wire [31:0] e_srl       = rs1_fwd >> e_shift_cnt;
wire [31:0] e_sra       = $signed(rs1_fwd) >>> e_shift_cnt;
wire [31:0] e_add       = rs1_fwd + e_arith_op2;
wire [31:0] e_sub       = rs1_fwd - e_arith_op2;
wire [31:0] e_xor       = rs1_fwd ^ e_arith_op2;
wire [31:0] e_or        = rs1_fwd | e_arith_op2;
wire [31:0] e_and       = rs1_fwd & e_arith_op2;
wire [31:0] e_lt        = {31'b0, $signed(rs1_fwd) < $signed(e_arith_op2)};
wire [31:0] e_ltu       = {31'b0, rs1_fwd < e_arith_op2};

wire [31:0] e_csr_val   = de_immed[15:0] == CSR_MARCHID ? 32'h72787600 :
                          de_immed[15:0] == CSR_MSCRATCH ? mscratch_reg :
                          de_immed[15:0] == CSR_MCAUSE ? mcause_reg :
                          de_immed[15:0] == CSR_MTVAL ? mtval_reg :
                          de_immed[15:0] == CSR_MTVEC ? mtvec_reg :
                          de_immed[15:0] == CSR_MIP ? mip_reg :
                          de_immed[15:0] == CSR_MIE ? mie_reg :
                          de_immed[15:0] == CSR_MCOUNTEREN ? mcounteren_reg :
                          de_immed[15:0] == CSR_MSTATUS ? mstatus_reg :
                          de_immed[15:0] == CSR_MEPC || de_do_mret ? mepc_reg :
                          de_immed[15:0] == CSR_MCYCLE ? mcycle_reg[31:0] :
                          de_immed[15:0] == CSR_MCYCLEH ? mcycle_reg[63:32] :
                          de_immed[15:0] == CSR_MINSTRET ? minstret_reg[31:0] :
                          de_immed[15:0] == CSR_MINSTRETH ? minstret_reg[63:32] :
                          32'h00000000;
wire [31:0] e_csr_wdata = de_funct3 == CSRRW ? rs1_fwd :
                          de_funct3 == CSRRS ? e_csr_val | rs1_fwd :
                          de_funct3 == CSRRC ? e_csr_val & ~rs1_fwd :
                          de_funct3 == CSRRWI ? {27'b0, de_csr_immed} :
                          de_funct3 == CSRRSI ? e_csr_val | {27'b0, de_csr_immed} :
                          de_funct3 == CSRRCI ? e_csr_val & ~{27'b0, de_csr_immed} :
                          rs1_fwd;
wire [31:0] e_next_pc   = de_br_type == BRANCH_NONE ? de_next_seq_pc :
                          de_br_type == BRANCH_IMMED ? de_branch_tgt :
                          e_branch_tgt;
wire e_instr_ac         = de_valid &&
                          de_br_type != BRANCH_NONE && e_next_pc[1];

// Memory cycles
assign d_access         = em_valid & (em_load | em_store) & !m_align_check;
assign d_wren           = em_valid & em_store;
wire [1:0] ls_addr_lsb  = em_result[1:0];
wire [3:0] d_bytesel_16 = ls_addr_lsb[1] ? 4'b1100 : 4'b0011;
wire [3:0] d_bytesel_8  = ls_addr_lsb[1:0] == 2'b00 ? 4'b0001 :
                          ls_addr_lsb[1:0] == 2'b01 ? 4'b0010 :
                          ls_addr_lsb[1:0] == 2'b10 ? 4'b0100 :
                          4'b1000;
assign d_bytesel        = em_valid && em_ls_width == LS_WIDTH_32 ? 4'b1111 :
                          em_valid && em_ls_width == LS_WIDTH_16 ? d_bytesel_16 :
                          em_valid && em_ls_width == LS_WIDTH_8 ? d_bytesel_8 : 4'b1111;
wire [31:0] d_wdata32   = em_store_data;
wire [31:0] d_wdata16   = ls_addr_lsb[1] ? {em_store_data[15:0], 16'b0} : em_store_data;
wire [31:0] d_wdata8    = ls_addr_lsb[1:0] == 2'b11 ? {em_store_data[7:0], 24'b0} :
                          ls_addr_lsb[1:0] == 2'b10 ? {8'b0, em_store_data[7:0], 16'b0} :
                          ls_addr_lsb[1:0] == 2'b01 ? {16'b0, em_store_data[7:0], 8'b0} :
                          em_store_data;
wire [1:0] mw_addr_lsb  = mw_result[1:0];
wire [31:0] d_rdata_rot = mw_addr_lsb[1:0] == 2'b11 ? {24'b0, d_rdata[31:24]} :
                          mw_addr_lsb[1:0] == 2'b10 ? {16'b0, d_rdata[31:16]} :
                          mw_addr_lsb[1:0] == 2'b01 ? {24'b0, d_rdata[15:8]} :
                          d_rdata;
wire [31:0] d_rdata_msk = mw_ls_width == LS_WIDTH_32 ? d_rdata_rot :
                          mw_ls_width == LS_WIDTH_16 ? {16'b0, d_rdata_rot[15:0]} :
                          {24'b0, d_rdata_rot[7:0]};
wire [31:0] d_rdata_s   = mw_ls_width == LS_WIDTH_16 ? {{17{d_rdata_rot[15]}}, d_rdata_rot[14:0]} :
                          mw_ls_width == LS_WIDTH_8 ? {{25{d_rdata_rot[7]}}, d_rdata_rot[6:0]} :
                          d_rdata_rot;
assign d_wdata          = em_ls_width == LS_WIDTH_32 ? d_wdata32 :
                          em_ls_width == LS_WIDTH_16 ? d_wdata16 : d_wdata8;
assign d_addr           = {em_result[31:2], 2'b00};
wire m_align_check      = em_ls_width == LS_WIDTH_32 ? |em_result[1:0] :
                          em_ls_width == LS_WIDTH_16 ? em_result[0] : 1'b0;
wire m_raise_ac         = em_valid && (em_load || em_store) && m_align_check;
wire m_abort            = m_raise_ac | w_exception;

wire [31:0] rs1_data, rs2_data;
wire [31:0] rs1_fwd = fwd_rs1_e ? em_result : fwd_rs1_m ? w_data : rs1_data;
wire [31:0] rs2_fwd = fwd_rs2_e ? em_result : fwd_rs2_m ? w_data : rs2_data;
reg [31:0] fd_pc;
reg fd_valid;
`ifdef RXV_RVFI
reg fd_intr;
`endif

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        flush_pipeline <= 1'b0;
        delay_slot <= 1'b0;
        fd_pc <= reset_vector;
        fd_valid <= 1'b0;
`ifdef RXV_RVFI
        fd_intr <= 1'b0;
`endif
    end else begin
        if (f_finish_flush)
            flush_pipeline <= 1'b0;
        if (f_flush_pipeline)
            flush_pipeline <= 1'b1;

        delay_slot <= d_load_delay && !w_exception;
        fd_pc <= next_pc;
        fd_valid <= !(d_load_delay || f_flush_pipeline || (flush_pipeline && !f_finish_flush)) || w_write_pc || e_write_pc || d_write_pc;
`ifdef RXV_RVFI
        fd_intr <= w_take_interrupt;
`endif
    end
end

// CSRs
// verilator lint_off BLKANDNBLK
reg [31:0] mscratch_reg;

reg [31:0] mtval_reg;

reg mcause_reg_i;
reg [3:0] mcause_reg_code;
wire [31:0] mcause_reg = {mcause_reg_i, 27'b0, mcause_reg_code};

reg [31:2] mtvec_reg_base;
reg mtvec_reg_mode;
wire [31:0] mtvec_reg = {mtvec_reg_base, 1'b0, mtvec_reg_mode};

reg [31:2] mepc_reg_msb;
wire [31:0] mepc_reg = {mepc_reg_msb, 2'b0};

reg mip_msip;
wire [31:0] mip_reg = {20'b0, intr_ext, 3'b0, intr_timer, 3'b0, mip_msip, 3'b0};

reg mcounteren_cy;
reg mcounteren_tm;
reg mcounteren_ir;
wire [31:0] mcounteren_reg = {29'b0, mcounteren_ir, mcounteren_tm, mcounteren_cy};

reg mie_msie;
reg mie_mtie;
reg mie_meie;
wire [31:0] mie_reg = {20'b0, mie_meie, 3'b0, mie_mtie, 3'b0, mie_msie, 3'b0};

reg mstatus_mie;
reg mstatus_mpie;
// Always in M-mode
wire [31:0] mstatus_reg = {19'b0, 2'b11, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
// verilator lint_on BLKANDNBLK

reg [63:0] mcycle_reg;
reg [63:0] minstret_reg;

always_ff @(posedge clk or posedge reset)
    if (reset) begin
        mcycle_reg <= 64'b0;
        minstret_reg <= 64'b0;
    end else begin
        mcycle_reg <= mcycle_reg + {63'b0, mcounteren_cy};
        minstret_reg <= minstret_reg + {63'b0, mcounteren_ir & mw_valid};
    end

reg [31:0] de_immed;
reg [31:0] de_pc;
reg [31:0] de_next_seq_pc;
reg [31:0] de_branch_tgt;
reg [4:0] de_rd;
reg de_writeback;
reg de_illegal_instr;
reg [31:0] de_instruction;
reg de_valid;
reg [1:0] de_br_type;
reg [2:0] de_funct3;
reg de_load;
reg de_store;
reg [1:0] de_ls_width;
reg de_load_sext;
`ifdef RXV_RVFI
reg de_read_csr;
reg de_intr;
`endif
reg de_write_csr;
reg [4:0] de_csr_immed;
reg de_do_mret;
reg de_do_ecall;
reg de_do_ebreak;
reg de_do_fence;
reg [3:0] de_alu_op;
reg de_op2_immed;
// Forward from end of exec stage back to start of exec?
reg fwd_rs1_e, fwd_rs2_e;
// Forward from end of mem stage back to start of exec?
reg fwd_rs1_m, fwd_rs2_m;

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
        de_illegal_instr <= fd_valid && d_illegal_instr && !w_exception;
        de_valid <= fd_valid && !e_instr_ac && !w_exception && !flush_pipeline && !w_exception && !d_illegal_instr && !m_abort;
        de_br_type <= fd_valid && !w_exception && !flush_pipeline && !w_exception && !d_illegal_instr ? d_br_type : 2'b00;
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
        de_do_mret <= fd_valid && !w_exception && !flush_pipeline && !w_exception && !d_illegal_instr && d_read_mepc;
        de_do_ecall <= fd_valid && !w_exception && !flush_pipeline && !w_exception && !d_illegal_instr && instruction == INSTR_ECALL;
        de_do_ebreak <= fd_valid && !w_exception && !flush_pipeline && !w_exception && !d_illegal_instr && instruction == INSTR_EBREAK;
        de_do_fence <= fd_valid && !w_exception && !flush_pipeline && !w_exception && !d_illegal_instr && d_fence;
        de_alu_op <= d_alu_op;
        de_op2_immed <= d_op2_immed;

        fwd_rs1_e <= |de_rd && de_valid && de_writeback && de_rd == rs1;
        fwd_rs2_e <= |de_rd && de_valid && de_writeback && de_rd == rs2;
    end
end

reg em_writeback;
reg [4:0] em_rd;
reg [31:0] em_result;
reg [31:0] em_pc;
reg [31:0] em_next_pc;
reg [31:0] em_instruction;
reg [31:0] em_store_data;
reg em_illegal_instr;
reg em_valid;
reg em_load;
reg em_store;
reg [1:0] em_ls_width;
reg [15:0] em_csr_rd;
reg em_load_sext;
reg em_write_csr;
reg [31:0] em_csr_wdata;
reg em_instr_align_check;
reg em_do_ecall;
reg em_do_ebreak;
reg em_do_fence;
reg em_do_mret;
`ifdef RXV_RVFI
reg em_intr;
`endif

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
        em_store_data <= rs2_fwd;
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

reg mw_writeback;
reg [4:0] mw_rd;
reg [31:0] mw_result;
// verilator lint_off UNUSED
reg [31:0] mw_pc;
// verilator lint_on UNUSED
reg [31:0] mw_next_pc;
reg [31:0] mw_instruction;
reg mw_illegal_instr;
reg mw_valid;
reg [1:0] mw_ls_width;
reg mw_load;
reg mw_load_sext;
reg mw_write_csr;
reg [15:0] mw_csr_rd;
reg [31:0] mw_csr_wdata;
reg mw_data_align_check;
reg mw_instr_align_check;
reg mw_do_ecall;
reg mw_do_ebreak;
reg mw_do_fence;
reg mw_do_mret;
`ifdef RXV_RVFI
reg mw_intr;
`endif
wire [31:0] w_data = mw_load ? (mw_load_sext ? d_rdata_s : d_rdata_msk) : mw_result;
wire w_wr_en = mw_valid && mw_writeback && !w_trap;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mw_writeback <= 1'b0;
        mw_rd <= 5'b0;
        mw_result <= 32'b0;
        mw_pc <= 32'b0;
        mw_instruction <= 32'b0;
        mw_next_pc <= 32'b0;
        mw_illegal_instr <= 1'b0;
        mw_valid <= 1'b0;
        mw_ls_width <= 2'b0;
        mw_load <= 1'b0;
        mw_load_sext <= 1'b0;
        mw_write_csr <= 1'b0;
        mw_csr_rd <= 16'b0;
        mw_csr_wdata <= 32'b0;
        mw_data_align_check <= 1'b0;
        mw_do_ecall <= 1'b0;
        mw_do_ebreak <= 1'b0;
        mw_do_fence <= 1'b0;
        mw_do_mret <= 1'b0;
        mw_instr_align_check <= 1'b0;
`ifdef RXV_RVFI
        mw_intr <= 1'b0;
`endif
    end else begin
        mw_writeback <= em_writeback && !m_abort && !w_exception;
        mw_rd <= em_rd;
        mw_result <= em_result;
        mw_pc <= em_pc;
        mw_instruction <= em_instruction;
        mw_next_pc <= em_next_pc;
        mw_illegal_instr <= em_illegal_instr && !w_exception;
        mw_valid <= em_valid && !w_exception;
        mw_ls_width <= em_ls_width;
        mw_load <= em_load;
        mw_load_sext <= em_load_sext;
        mw_write_csr <= em_write_csr;
        mw_csr_rd <= em_csr_rd;
        mw_csr_wdata <= em_csr_wdata;
        mw_data_align_check <= m_raise_ac && !w_exception;
        mw_do_ecall <= em_do_ecall && !w_exception;
        mw_do_ebreak <= em_do_ebreak && !w_exception;
        mw_do_fence <= em_do_fence && !w_exception;
        mw_do_mret <= em_do_mret && !w_exception;
        mw_instr_align_check <= em_instr_align_check && !w_exception;
`ifdef RXV_RVFI
        mw_intr <= em_intr;
`endif
    end
end

wire csr_mscratch_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MSCRATCH;
`ifdef RXV_RVFI
wire csr_mscratch_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MSCRATCH;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        mscratch_reg <= 32'b0;
    else begin
        if (csr_mscratch_w)
            mscratch_reg <= mw_csr_wdata;
`ifdef RXV_RVFI
        {rvfi_csr_mscratch_wmask, rvfi_csr_mscratch_wdata} <= csr_mscratch_w ?
            {32'hffffffff, mw_csr_wdata} : 64'b0;
        rvfi_csr_mscratch_pipe <= {rvfi_csr_mscratch_pipe[63:0], csr_mscratch_r ?
            32'hffffffff : 32'h00000000, e_csr_val};
        {rvfi_csr_mscratch_rmask, rvfi_csr_mscratch_rdata} <=
            rvfi_csr_mscratch_pipe[127:64];
`endif
    end

wire csr_mcause_w = w_exception || (mw_valid && mw_write_csr && mw_csr_rd == CSR_MCAUSE);
`ifdef RXV_RVFI
wire csr_mcause_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MCAUSE;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mcause_reg_i, mcause_reg_code} <= 5'b0;
    else begin
        if (w_exception)
            {mcause_reg_i, mcause_reg_code} <= {w_mcause_i, w_mcause_code};
        else if (csr_mcause_w)
            {mcause_reg_i, mcause_reg_code} <= {mw_csr_wdata[31], mw_csr_wdata[3:0]};
`ifdef RXV_RVFI
        {rvfi_csr_mcause_wmask, rvfi_csr_mcause_wdata} <=
            w_exception ? {32'hffffffff, w_mcause_i, 27'b0, w_mcause_code} :
            csr_mcause_w ? {32'hffffffff, mw_csr_wdata} : 64'b0;
        rvfi_csr_mcause_pipe <= {rvfi_csr_mcause_pipe[63:0], csr_mcause_r ?
            32'hffffffff : 32'h00000000, e_csr_val};
        {rvfi_csr_mcause_rmask, rvfi_csr_mcause_rdata} <= rvfi_csr_mcause_pipe[127:64];

`endif
    end

wire csr_mtvec_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MTVEC;
`ifdef RXV_RVFI
wire csr_mtvec_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MTVEC;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mtvec_reg_base, mtvec_reg_mode} <= 31'b0;
    else begin
        if (csr_mtvec_w)
            {mtvec_reg_base, mtvec_reg_mode} <= {mw_csr_wdata[31:2], mw_csr_wdata[0]};
`ifdef RXV_RVFI
        {rvfi_csr_mtvec_wmask, rvfi_csr_mtvec_wdata} <= csr_mtvec_w ?
            {32'hffffffff, mw_csr_wdata} : 64'b0;
        rvfi_csr_mtvec_pipe <= {rvfi_csr_mtvec_pipe[63:0], csr_mtvec_r ?
            32'hffffffff : 32'h00000000, e_csr_val};
        {rvfi_csr_mtvec_rmask, rvfi_csr_mtvec_rdata} <= w_exception ?
            {32'hffffffff, mtvec_reg} : rvfi_csr_mtvec_pipe[127:64];
`endif
    end

wire csr_mepc_w = w_trap || w_take_interrupt || (mw_valid && mw_write_csr && mw_csr_rd == CSR_MEPC);
`ifdef RXV_RVFI
wire csr_mepc_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MEPC || de_do_mret;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        mepc_reg_msb <= 30'b0;
    else begin
        if (w_trap)
            mepc_reg_msb <= mw_pc[31:2];
        else if (w_take_interrupt)
            mepc_reg_msb <= mw_next_pc[31:2];
        else if (csr_mepc_w)
            mepc_reg_msb <= mw_csr_wdata[31:2];
`ifdef RXV_RVFI
        {rvfi_csr_mepc_wmask, rvfi_csr_mepc_wdata} <=
            w_trap ? {32'hffffffff, mw_pc[31:2], 2'b0} :
            w_take_interrupt ? {32'hffffffff, mw_next_pc[31:2], 2'b0} :
            csr_mepc_w ? {32'hffffffff, mw_csr_wdata} : 64'b0;
        rvfi_csr_mepc_pipe <= {rvfi_csr_mepc_pipe[63:0], csr_mepc_r ?
            32'hffffffff : 32'h00000000, e_csr_val};
        {rvfi_csr_mepc_rmask, rvfi_csr_mepc_rdata} <= rvfi_csr_mepc_pipe[127:64];
`endif
    end

wire csr_mtval_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MTVAL;
`ifdef RXV_RVFI
wire csr_mtval_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MTVAL;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        mtval_reg <= 32'b0;
    else begin
        if (w_exception)
            mtval_reg <= w_mtval;
        else if (csr_mtval_w)
            mtval_reg <= mw_csr_wdata;
`ifdef RXV_RVFI
        {rvfi_csr_mtval_wmask, rvfi_csr_mtval_wdata} <=
            w_exception ? {32'hffffffff, w_mtval} :
            csr_mtval_w ? {32'hffffffff, mw_csr_wdata} :
            64'b0;
        rvfi_csr_mtval_pipe <= {rvfi_csr_mtval_pipe[63:0], csr_mtval_r ?
            32'hffffffff : 32'h00000000, e_csr_val};
        {rvfi_csr_mtval_rmask, rvfi_csr_mtval_rdata} <= rvfi_csr_mtval_pipe[127:64];

`endif
    end

wire csr_mip_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MIP;
`ifdef RXV_RVFI
wire csr_mip_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MIP;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        mip_msip <= 1'b0;
    else begin
        if (csr_mip_w)
            mip_msip <= mw_csr_wdata[3];
`ifdef RXV_RVFI
        {rvfi_csr_mip_wmask, rvfi_csr_mip_wdata} <=
            csr_mip_w ? {32'hffffffff, mw_csr_wdata} : 64'b0;
        rvfi_csr_mip_pipe <= {rvfi_csr_mip_pipe[63:0], csr_mip_r ?
            32'h00000888 : 32'h00000000, e_csr_val};
        {rvfi_csr_mip_rmask, rvfi_csr_mip_rdata} <= rvfi_csr_mip_pipe[127:64];

`endif
    end

wire csr_mcounteren_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MCOUNTEREN;

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mcounteren_ir, mcounteren_tm, mcounteren_cy} <= 3'b111;
    else begin
        if (csr_mcounteren_w)
            {mcounteren_ir, mcounteren_tm, mcounteren_cy} <= mw_csr_wdata[2:0];
    end

wire csr_mie_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MIE;
`ifdef RXV_RVFI
wire csr_mie_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MIE;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mie_meie, mie_mtie, mie_msie} <= 3'b0;
    else begin
        if (csr_mie_w)
            {mie_meie, mie_mtie, mie_msie} <= {mw_csr_wdata[11], mw_csr_wdata[7], mw_csr_wdata[3]};
`ifdef RXV_RVFI
        {rvfi_csr_mie_wmask, rvfi_csr_mie_wdata} <=
            csr_mie_w ? {32'hffffffff, mw_csr_wdata} : 64'b0;
        rvfi_csr_mie_pipe <= {rvfi_csr_mie_pipe[63:0], csr_mie_r ?
            32'h00000888 : 32'h00000000, e_csr_val};
        {rvfi_csr_mie_rmask, rvfi_csr_mie_rdata} <= rvfi_csr_mie_pipe[127:64];
`endif
    end

wire csr_mstatus_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MSTATUS;
`ifdef RXV_RVFI
wire csr_mstatus_r = de_valid && de_read_csr && de_immed[15:0] == CSR_MSTATUS;
`endif

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mstatus_mpie, mstatus_mie} <= 2'b0;
    else begin
        if (w_exception)
            {mstatus_mpie, mstatus_mie} <= {mstatus_mie, 1'b0};
        else if (mw_do_mret)
            {mstatus_mpie, mstatus_mie} <= {1'b1, mstatus_mpie};
        else if (mw_valid && mw_write_csr && mw_csr_rd == CSR_MSTATUS)
            {mstatus_mpie, mstatus_mie} <= {mw_csr_wdata[7], mw_csr_wdata[3]};
`ifdef RXV_RVFI
        {rvfi_csr_mstatus_wmask, rvfi_csr_mstatus_wdata} <=
            w_exception ? {32'h00001808, 19'b0, 2'b11, 3'b0, mstatus_mie, 3'b0, 1'b0, 3'b0} :
            mw_do_mret ? {32'h00001808, 19'b0, 2'b11, 3'b0, 1'b1, 3'b0, mstatus_mpie, 3'b0} :
            csr_mstatus_w ? {32'h00001808, mw_csr_wdata} : 64'b0;
        rvfi_csr_mstatus_pipe <= {rvfi_csr_mstatus_pipe[63:0], csr_mstatus_r ?
            32'h00001808 : 32'h00000000, e_csr_val};
        {rvfi_csr_mstatus_rmask, rvfi_csr_mstatus_rdata} <= rvfi_csr_mstatus_pipe[127:64];
`endif
    end

RegFile RegFile(.clk(clk),
		.reset(reset),
		.rd_addr_a(rs1),
                .rd_data_a(rs1_data),
                .rd_addr_b(rs2),
                .rd_data_b(rs2_data),
                .wr_en(w_wr_en),
                .wr_addr(mw_rd),
                .wr_data(w_data));

always_ff @(posedge clk or posedge reset)
    if (reset)
        pc <= reset_vector - 32'd4;
    else begin
        pc <= next_pc;
    end

wire w_take_interrupt = !mw_write_csr &
                        mw_valid &
                        ~w_trap &
                        mstatus_mie &
                        ((intr_ext & mie_meie) |
                          (intr_timer & mie_mtie) |
                          (mip_msip & mie_msie));

wire w_trap              = mw_data_align_check |
                           mw_illegal_instr |
                           mw_instr_align_check |
                           mw_do_ecall |
                           mw_do_ebreak;
wire w_exception         = w_trap |
                           w_take_interrupt;
wire [3:0] w_int_cause   = intr_ext & mie_meie ? 4'd8 :
                           mip_msip & mie_msie ? 4'd3 :
                           intr_timer & mie_mtie ? 4'd7 :
                           4'd7;
wire w_mcause_i;
wire [3:0] w_mcause_code;

assign {w_mcause_i, w_mcause_code} =
                           mw_data_align_check && mw_load ? {1'b0, EX_LOAD_ALIGN}:
                           mw_data_align_check && !mw_load ? {1'b0, EX_STORE_ALIGN} :
                           mw_illegal_instr ? {1'b0, EX_ILLEGAL_INSTR} :
                           mw_instr_align_check ? {1'b0, EX_INSTR_ALIGN} :
                           mw_do_ecall ? {1'b0, EX_ECALL_M} :
                           mw_do_ebreak ? {1'b0, EX_BREAKPOINT} :
                           w_take_interrupt ? {1'b1, w_int_cause} :
                           5'd0;
wire [31:0] w_irq_addr   = mtvec_reg_mode == 1'b0 || !w_mcause_i ?
                           {mtvec_reg_base, 2'b0} :
                           {mtvec_reg_base, 2'b0} + {26'b0, w_mcause_code, 2'b0};
wire [31:0] w_mtval      = mw_data_align_check ? mw_result :
                           mw_illegal_instr ? mw_instruction :
                           mw_instr_align_check ? mw_next_pc : 32'b0;
wire [31:0] w_next_pc    = w_exception ? w_irq_addr :
                           mw_result;
wire w_write_pc          = w_exception || mw_do_mret;

`ifdef RXV_RVFI
reg [127:0] rvfi_csr_marchid_pipe;
reg [127:0] rvfi_csr_mscratch_pipe;
reg [127:0] rvfi_csr_mcause_pipe;
reg [127:0] rvfi_csr_mtvec_pipe;
reg [127:0] rvfi_csr_mtval_pipe;
reg [127:0] rvfi_csr_mepc_pipe;
reg [127:0] rvfi_csr_mip_pipe;
reg [127:0] rvfi_csr_mie_pipe;
reg [127:0] rvfi_csr_mstatus_pipe;

assign rvfi_csr_marchid_wmask = 32'h0;
assign rvfi_csr_marchid_wdata = 32'd0;
assign rvfi_halt = 1'b0;
assign rvfi_mode = 2'b11;
assign rvfi_ixl = 2'b01;

reg [63:0] rvfi_mem_addr_pipe;
reg [7:0] rvfi_mem_rmask_pipe;
reg [7:0] rvfi_mem_wmask_pipe;
reg [63:0] rvfi_mem_wdata_pipe;
reg [95:0] rvfi_rs1_rdata_pipe;
reg [95:0] rvfi_rs2_rdata_pipe;
reg [19:0] rvfi_rs1_addr_pipe;
reg [19:0] rvfi_rs2_addr_pipe;

assign rvfi_mem_addr = rvfi_mem_addr_pipe[63:32];
assign rvfi_mem_rmask = rvfi_mem_rmask_pipe[7:4];
assign rvfi_mem_wmask = rvfi_mem_wmask_pipe[7:4];
assign rvfi_mem_wdata = rvfi_mem_wdata_pipe[63:32];
assign rvfi_rs1_rdata = rvfi_rs1_rdata_pipe[95:64];
assign rvfi_rs2_rdata = rvfi_rs2_rdata_pipe[95:64];
assign rvfi_rs1_addr = rvfi_rs1_addr_pipe[19:15];
assign rvfi_rs2_addr = rvfi_rs2_addr_pipe[19:15];

wire rvfi_retire = mw_valid | w_trap;

initial begin
    rvfi_valid = 1'b0;
    rvfi_order = 64'b0;
    rvfi_trap = 1'b0;
end

always_ff @(posedge clk) begin
    rvfi_valid <= rvfi_retire;
    rvfi_pc_rdata <= mw_pc;
    rvfi_pc_wdata <= w_write_pc && !w_take_interrupt ? w_next_pc : mw_next_pc;
    rvfi_insn <= mw_instruction;
    rvfi_rd_addr <= mw_valid && mw_writeback ? mw_rd : 5'b0;
    rvfi_rd_wdata <= mw_valid && mw_writeback && mw_rd != 5'd0 ? w_data : 32'b0;
    rvfi_order <= rvfi_order + {63'b0, rvfi_retire};
    rvfi_trap <= w_trap;
    rvfi_mem_rdata <= d_rdata;
    rvfi_intr <= mw_intr;

    rvfi_mem_addr_pipe <= {rvfi_mem_addr_pipe[31:0], d_addr};
    rvfi_mem_rmask_pipe <= {rvfi_mem_rmask_pipe[3:0], d_access && ~d_wren && ~m_align_check ? d_bytesel : 4'b0};
    rvfi_mem_wmask_pipe <= {rvfi_mem_wmask_pipe[3:0], d_access && d_wren && ~m_align_check ? d_bytesel : 4'b0};
    rvfi_mem_wdata_pipe <= {rvfi_mem_wdata_pipe[31:0], d_wren ? d_wdata : 32'b0};
    rvfi_rs1_rdata_pipe <= {rvfi_rs1_rdata_pipe[63:0], rs1_fwd};
    rvfi_rs2_rdata_pipe <= {rvfi_rs2_rdata_pipe[63:0], rs2_fwd};
    rvfi_rs1_addr_pipe <= {rvfi_rs1_addr_pipe[14:0], rs1};
    rvfi_rs2_addr_pipe <= {rvfi_rs2_addr_pipe[14:0], rs2};

    // MARCHID
    rvfi_csr_marchid_pipe <= {rvfi_csr_marchid_pipe[63:0], de_valid && de_read_csr && de_immed[15:0] == CSR_MARCHID ? 32'hffffffff : 32'h00000000, e_csr_val};
    {rvfi_csr_marchid_rmask, rvfi_csr_marchid_rdata} <= rvfi_csr_marchid_pipe[127:64];
end

always_ff @(posedge clk) begin
    if (!mstatus_mie)
        assert(!w_take_interrupt);
    if (fd_intr)
        assert(!mstatus_mie);
end

`ifdef verilator
export "DPI-C" function write_csr;
export "DPI-C" function write_pc;
export "DPI-C" function set_reset_vector;

function void write_csr;
    input int csr;
    input int val;

    case (csr[15:0])
    CSR_MTVEC: {mtvec_reg_base, mtvec_reg_mode} = {val[31:2], val[0]};
    CSR_MEPC: mepc_reg_msb = val[31:2];
    CSR_MSTATUS: {mstatus_mpie, mstatus_mie} = {val[7], val[3]};
    CSR_MIP: mip_msip = val[3];
    CSR_MIE: mie_msie = val[3];
    default: $display("unsupported CSR %x", csr);
    endcase
endfunction

function void set_reset_vector;
    input int val;

    reset_vector = val;
endfunction

function void write_pc;
    input int val;

    pc = val;
endfunction

`endif // verilator
`endif // RXV_RVFI

endmodule
