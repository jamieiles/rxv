module RXVCore(input logic clk,
               input logic reset,
               // Instruction bus
               output logic [31:0] i_addr,
               input logic [31:0] i_data,
               // Data bus
               output logic d_access,
               output logic d_wren,
               output logic [31:0] d_addr,
               output logic [3:0] d_bytesel,
               output logic [31:0] d_wdata,
               input logic [31:0] d_rdata,
               // RVFI
               output logic rvfi_valid,
               output logic [31:0] rvfi_insn,
               output logic [4:0] rvfi_rd_addr,
               output logic [31:0] rvfi_rd_wdata,
               output logic [31:0] rvfi_pc_rdata,
               output logic [31:0] rvfi_pc_wdata,
               // verilator lint_off UNUSED
               // verilator lint_off UNDRIVEN
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
               output logic [31:0] rvfi_csr_mscratch_wdata);
               // verilator lint_on UNDRIVEN
               // verilator lint_on UNUSED

// Instruction fetch
reg [31:0] pc;
wire [31:0] instruction = i_data;
wire [31:0] next_pc     = w_exception ? w_next_pc :
                          ef_write_pc ? em_next_pc :
                          insert_bubble ? pc : pc + 32'd4;
assign i_addr           = pc;
reg insert_bubble;

wire f_clear_bubble     = ef_write_pc |
                          de_load |
                          mw_write_csr |
                          w_exception;
wire f_insert_bubble    = d_is_branch |
                          d_opcode == OPC_LOAD |
                          d_write_csr |
                          d_abort |
                          d_illegal_instr;

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

localparam OPC_LUI      = 7'b0110111,
           OPC_AUIPC    = 7'b0010111,
           OPC_JAL      = 7'b1101111,
           OPC_JALR     = 7'b1100111,
           OPC_BRANCH   = 7'b1100011,
           OPC_LOAD     = 7'b0000011,
           OPC_STORE    = 7'b0100011,
           OPC_ARITHI   = 7'b0010011,
           OPC_ARITH    = 7'b0110011,
           OPC_FENCE    = 7'b0001111,
           OPC_ENV      = 7'b1110011;

localparam BR_BEQ       = 3'b000,
           BR_BNE       = 3'b001,
           BR_BLT       = 3'b100,
           BR_BGE       = 3'b101,
           BR_BLTU      = 3'b110,
           BR_BGEU      = 3'b111;

localparam INSTR_ECALL  = 32'h00000073,
           INSTR_EBREAK = 32'h00100073,
           INSTR_MRET   = 32'h30200073;

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
           CSR_MIP          = 16'h0344;

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
                          d_opcode == OPC_AUIPC ? u_immed :
                          d_opcode == OPC_JAL ? j_immed :
                          d_opcode == OPC_JALR ? i_immed_s :
                          d_opcode == OPC_LOAD ? i_immed_s :
                          d_opcode == OPC_ARITHI ? i_immed_s :
                          d_opcode == OPC_BRANCH ? b_immed :
                          d_opcode == OPC_STORE ? s_immed :
                          d_opcode == OPC_ENV ? i_immed : i_immed;

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
                          ((funct3 == 3'd0 || funct7 == 7'd5) && |{funct7[6], funct7[4:0]});
wire d_bad_env          = d_opcode == OPC_ENV &&
                          (funct3 == 3'd4 ||
                           (funct3 == 3'd0 &&
                            !(instruction == INSTR_ECALL ||
                             instruction == INSTR_EBREAK ||
                             instruction == INSTR_MRET)));
wire d_illegal_instr    = d_bad_opc | d_bad_branch | d_bad_load | d_bad_store |
                          d_bad_arithi | d_bad_arith | d_bad_env;
wire [1:0] d_br_type    = d_opcode == OPC_JAL ? BRANCH_IMMED :
                          d_opcode == OPC_JALR ? BRANCH_INDIR :
                          d_opcode == OPC_BRANCH ? BRANCH_COND : BRANCH_NONE;
wire [1:0] d_ls_width   = funct3[1:0];
wire d_load_sext        = ~funct3[2];
wire d_abort            = e_abort;

// Instruction execution
wire e_sub_b;
wire [31:0] e_sub;
wire [31:0] alu_out     = de_opcode == OPC_LUI ? de_immed :
                          de_opcode == OPC_AUIPC ? de_immed + de_pc :
                          de_opcode == OPC_JAL ? de_pc + 32'd4 :
                          de_opcode == OPC_JALR ? de_pc + 32'd4 :
                          de_opcode == OPC_ARITHI || de_opcode == OPC_ARITH ? e_arith_res :
                          de_opcode == OPC_STORE ? rs1_fwd + de_immed :
                          de_opcode == OPC_LOAD ? rs1_fwd + de_immed :
                          de_opcode == OPC_ENV && de_read_csr ? e_csr_val :
                          de_immed;
// verilator lint_off UNUSED
wire [31:0] e_indir_tgt = rs1_fwd + de_immed;
// verilator lint_on UNUSED
wire [31:0] e_next_pc   = de_br_type == BRANCH_IMMED ? de_pc + de_immed :
                          de_br_type == BRANCH_INDIR ? {e_indir_tgt[31:1], 1'b0} :
                          de_br_type == BRANCH_COND && e_br_taken ? de_pc + de_immed :
                          de_pc + 32'd4;
wire e_write_pc         = de_br_type == BRANCH_IMMED ||
                          de_br_type == BRANCH_INDIR ||
                          (de_br_type == BRANCH_COND && e_br_taken);
wire e_br_taken         = de_funct3 == 3'd0 ? rs1_fwd == rs2_fwd :
                          de_funct3 == 3'd1 ? rs1_fwd != rs2_fwd :
                          de_funct3 == 3'd4 ? e_sub[31] :
                          de_funct3 == 3'd5 ? ~e_sub[31] :
                          de_funct3 == 3'd6 ? e_sub_b :
                          de_funct3 == 3'd7 ? ~e_sub_b: 1'b0;
wire [31:0] e_arith_op2 = de_opcode == OPC_ARITHI ? de_immed : rs2_fwd;
wire [4:0] e_shift_cnt  = de_opcode == OPC_ARITHI ? de_immed[4:0] : rs2_fwd[4:0];
wire [31:0] e_sll       = rs1_fwd << e_shift_cnt;
wire [31:0] e_srl       = rs1_fwd >> e_shift_cnt;
wire [31:0] e_sra       = $signed(rs1_fwd) >>> e_shift_cnt;
wire [31:0] e_add       = rs1_fwd + e_arith_op2;
wire [31:0] e_xor       = rs1_fwd ^ e_arith_op2;
wire [31:0] e_or        = rs1_fwd | e_arith_op2;
wire [31:0] e_and       = rs1_fwd & e_arith_op2;
wire [31:0] e_lt        = {31'b0, e_sub[31]};
wire [31:0] e_ltu       = {31'b0, e_sub_b};
wire [31:0] e_arith_res = de_opcode == OPC_ARITH && de_funct3 == 3'd0 && ~de_funct7_sel ? e_add :
                          de_opcode == OPC_ARITH && de_funct3 == 3'd0 &&  de_funct7_sel ? e_sub :
                          de_opcode == OPC_ARITHI && de_funct3 == 3'd0 ? e_add :
                          de_funct3 == 3'd1 ? e_sll :
                          de_funct3 == 3'd2 ? e_lt :
                          de_funct3 == 3'd3 ? e_ltu :
                          de_funct3 == 3'd4 ? e_xor :
                          de_funct3 == 3'd5 && ~de_funct7_sel ? e_srl :
                          de_funct3 == 3'd5 &&  de_funct7_sel ? e_sra :
                          de_funct3 == 3'd6 ? e_or :
                          de_funct3 == 3'd7 ? e_and :
                          e_add;
wire [31:0] e_csr_val   = de_immed[15:0] == CSR_MARCHID ? 32'h72787600 :
                          de_immed[15:0] == CSR_MSCRATCH ? mscratch_reg :
                          de_immed[15:0] == CSR_MCAUSE ? mcause_reg :
                          de_immed[15:0] == CSR_MTVAL ? mtval_reg :
                          de_immed[15:0] == CSR_MTVEC ? mtvec_reg :
                          de_immed[15:0] == CSR_MEPC ? mepc_reg :
                          32'h00000000;
wire [31:0] e_csr_wdata = de_funct3 == CSRRW ? rs1_fwd :
                          de_funct3 == CSRRS ? e_csr_val | rs1_fwd :
                          de_funct3 == CSRRC ? e_csr_val & ~rs1_fwd :
                          de_funct3 == CSRRWI ? {27'b0, de_csr_immed} :
                          de_funct3 == CSRRSI ? e_csr_val | {27'b0, de_csr_immed} :
                          de_funct3 == CSRRCI ? e_csr_val & ~{27'b0, de_csr_immed} :
                          rs1_fwd;
assign {e_sub_b, e_sub} = {1'b0, rs1_fwd} - {1'b0, e_arith_op2};
reg ef_write_pc;
wire e_abort            = m_abort;

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
                          mw_ls_width == LS_WIDTH_8 ? {24'b0, d_rdata_rot[7:0]} : 32'b0;
wire [31:0] d_rdata_s   = mw_ls_width == LS_WIDTH_16 ? {{17{d_rdata_rot[15]}}, d_rdata_rot[14:0]} :
                          mw_ls_width == LS_WIDTH_8 ? {{25{d_rdata_rot[7]}}, d_rdata_rot[6:0]} :
                          d_rdata_rot;
assign d_wdata          = em_ls_width == LS_WIDTH_32 ? d_wdata32 :
                          em_ls_width == LS_WIDTH_16 ? d_wdata16 : d_wdata8;
assign d_addr           = {em_result[31:2], 2'b00};
wire m_align_check      = em_ls_width == LS_WIDTH_32 ? |em_result[1:0] :
                          em_ls_width == LS_WIDTH_16 ? em_result[0] : 1'b0;
wire m_raise_ac         = em_valid && (em_load || em_store) && m_align_check;
wire m_abort            = m_raise_ac;

wire [31:0] rs1_data, rs2_data;
wire [31:0] rs1_fwd = fwd_rs1_e ? em_result : fwd_rs1_m ? w_data : rs1_data;
wire [31:0] rs2_fwd = fwd_rs2_e ? em_result : fwd_rs2_m ? w_data : rs2_data;

always_ff @(posedge clk) begin
    if (f_clear_bubble)
        insert_bubble <= 1'b0;
    else if (f_insert_bubble)
        insert_bubble <= 1'b1;
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
// verilator lint_on BLKANDNBLK

reg [6:0] de_opcode;
reg [31:0] de_immed;
reg [31:0] de_pc;
reg [4:0] de_rd;
reg de_writeback;
reg de_illegal_instr;
reg [31:0] de_instruction;
reg de_valid;
reg [1:0] de_br_type;
reg [2:0] de_funct3;
reg de_funct7_sel;
reg de_load;
reg de_store;
reg [1:0] de_ls_width;
reg de_load_sext;
reg de_read_csr;
reg de_write_csr;
reg [4:0] de_csr_immed;
// Forward from end of exec stage back to start of exec?
reg fwd_rs1_e, fwd_rs2_e;
// Forward from end of mem stage back to start of exec?
reg fwd_rs1_m, fwd_rs2_m;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        de_valid <= 1'b0;
    end else begin
        de_opcode <= d_opcode;
        de_immed <= d_immed;
        de_writeback <= d_writeback;
        de_instruction <= instruction;
        de_rd <= d_rd;
        de_pc <= pc;
        de_illegal_instr <= d_illegal_instr;
        de_valid <= !insert_bubble && !d_abort;
        de_br_type <= d_br_type;
        de_funct3 <= funct3;
        de_funct7_sel <= funct7[5];
        de_load <= d_opcode == OPC_LOAD;
        de_store <= d_opcode == OPC_STORE;
        de_ls_width <= d_ls_width;
        de_load_sext <= d_load_sext;
        de_read_csr <= d_read_csr;
        de_write_csr <= d_write_csr;
        de_csr_immed <= rs1;

        fwd_rs1_e <= de_valid && de_writeback && de_rd == rs1;
        fwd_rs2_e <= de_valid && de_writeback && de_rd == rs2;
    end
end

reg em_writeback;
reg [4:0] em_rd;
reg [31:0] em_result;
reg [31:0] em_pc, em_next_pc;
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

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        em_valid <= 1'b0;
    end else begin
        em_writeback <= de_valid && de_writeback;
        em_rd <= de_rd;
        em_result <= alu_out;
        em_pc <= de_pc;
        em_instruction <= de_instruction;
        em_next_pc <= e_next_pc;
        em_illegal_instr <= de_illegal_instr;
        em_valid <= de_valid && !e_abort;
        em_store_data <= rs2_fwd;
        em_load <= de_load;
        em_store <= de_store;
        em_ls_width <= de_ls_width;
        em_load_sext <= de_load_sext;
        em_write_csr <= de_write_csr;
        em_csr_rd <= de_immed[15:0];
        em_csr_wdata <= e_csr_wdata;

        fwd_rs1_m <= em_valid && em_writeback && em_rd == rs1;
        fwd_rs2_m <= em_valid && em_writeback && em_rd == rs2;

        ef_write_pc <= de_valid && e_write_pc;
    end
end

reg mw_writeback;
reg [4:0] mw_rd;
reg [31:0] mw_result;
reg [31:0] mw_pc, mw_next_pc;
reg [31:0] mw_instruction;
reg mw_illegal_instr;
reg mw_valid;
reg [1:0] mw_ls_width;
reg mw_load;
reg mw_load_sext;
reg mw_write_csr;
reg [15:0] mw_csr_rd;
reg [31:0] mw_csr_wdata;
reg mw_align_check;
wire [31:0] w_data = mw_load ? (mw_load_sext ? d_rdata_s : d_rdata_msk) : mw_result;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mw_valid <= 1'b0;
    end else begin
        mw_writeback <= em_writeback && !m_raise_ac;
        mw_rd <= em_rd;
        mw_result <= em_result;
        mw_pc <= em_pc;
        mw_instruction <= em_instruction;
        mw_next_pc <= em_next_pc;
        mw_illegal_instr <= em_illegal_instr;
        mw_valid <= em_valid;
        mw_ls_width <= em_ls_width;
        mw_load <= em_load;
        mw_load_sext <= em_load_sext;
        mw_write_csr <= em_write_csr;
        mw_csr_rd <= em_csr_rd;
        mw_csr_wdata <= em_csr_wdata;
        mw_align_check <= m_raise_ac;
    end
end

always_ff @(posedge clk or posedge reset)
    if (reset)
        mscratch_reg <= 32'b0;
    else if (mw_valid && mw_write_csr && mw_csr_rd == CSR_MSCRATCH)
        mscratch_reg <= mw_csr_wdata;

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mcause_reg_i, mcause_reg_code} <= 5'b0;
    else begin
        if (w_exception)
            {mcause_reg_i, mcause_reg_code} <= {w_mcause_i, w_mcause_code};
        if (mw_valid && mw_write_csr && mw_csr_rd == CSR_MCAUSE)
            {mcause_reg_i, mcause_reg_code} <= {mw_csr_wdata[31], mw_csr_wdata[3:0]};
    end

always_ff @(posedge clk or posedge reset)
    if (reset)
        {mtvec_reg_base, mtvec_reg_mode} <= 31'b0;
    else if (mw_valid && mw_write_csr && mw_csr_rd == CSR_MTVEC)
            {mtvec_reg_base, mtvec_reg_mode} <= {mw_csr_wdata[31:2], mw_csr_wdata[0]};

always_ff @(posedge clk or posedge reset)
    if (reset)
        mepc_reg_msb <= 30'b0;
    else begin
        if (w_exception)
            mepc_reg_msb <= mw_pc[31:2];
        if (mw_valid && mw_write_csr && mw_csr_rd == CSR_MEPC)
            mepc_reg_msb <= mw_csr_wdata[31:2];
    end

always_ff @(posedge clk or posedge reset)
    if (reset)
        mtval_reg <= 32'b0;
    else begin
        if (w_exception && mw_align_check)
            mtval_reg <= w_mtval;
        if (mw_valid && mw_write_csr && mw_csr_rd == CSR_MTVAL)
            mtval_reg <= mw_csr_wdata;
    end

RegFile RegFile(.rd_addr_a(rs1),
                .rd_data_a(rs1_data),
                .rd_addr_b(rs2),
                .rd_data_b(rs2_data),
                .wr_en(mw_writeback),
                .wr_addr(mw_rd),
                .wr_data(w_data),
                .*);

always_ff @(posedge clk or posedge reset)
    if (reset)
        pc <= 32'b0;
    else begin
        pc <= next_pc;
    end

reg [31:0] rvfi_em_csr_marchid_rmask;
reg [31:0] rvfi_em_csr_marchid_rdata;
reg [31:0] rvfi_mw_csr_marchid_rmask;
reg [31:0] rvfi_mw_csr_marchid_rdata;

reg [31:0] rvfi_em_csr_mscratch_rmask;
reg [31:0] rvfi_em_csr_mscratch_rdata;
reg [31:0] rvfi_mw_csr_mscratch_rmask;
reg [31:0] rvfi_mw_csr_mscratch_rdata;

reg [31:0] rvfi_em_csr_mcause_rmask;
reg [31:0] rvfi_em_csr_mcause_rdata;
reg [31:0] rvfi_mw_csr_mcause_rmask;
reg [31:0] rvfi_mw_csr_mcause_rdata;

reg [31:0] rvfi_em_csr_mtvec_rmask;
reg [31:0] rvfi_em_csr_mtvec_rdata;
reg [31:0] rvfi_mw_csr_mtvec_rmask;
reg [31:0] rvfi_mw_csr_mtvec_rdata;

reg [31:0] rvfi_em_csr_mtval_rmask;
reg [31:0] rvfi_em_csr_mtval_rdata;
reg [31:0] rvfi_mw_csr_mtval_rmask;
reg [31:0] rvfi_mw_csr_mtval_rdata;

reg [31:0] rvfi_em_csr_mepc_rmask;
reg [31:0] rvfi_em_csr_mepc_rdata;
reg [31:0] rvfi_mw_csr_mepc_rmask;
reg [31:0] rvfi_mw_csr_mepc_rdata;

wire w_exception         = mw_align_check | mw_illegal_instr;
wire w_mcause_i          = 1'b0;
wire [3:0] w_mcause_code = mw_align_check && mw_load ? EX_LOAD_ALIGN:
                           mw_align_check && !mw_load ? EX_STORE_ALIGN :
                           mw_illegal_instr ? EX_ILLEGAL_INSTR :
                           4'd0;
wire [31:0] w_mtval      = mw_align_check ? mw_result :
                           mw_illegal_instr ? mw_instruction : 32'b0;
wire [31:0] w_next_pc    = w_exception ? {mtvec_reg_base, 2'b0} : mw_next_pc;

always_ff @(posedge clk) begin
    rvfi_valid <= mw_valid;
    rvfi_pc_rdata <= mw_pc;
    rvfi_pc_wdata <= w_next_pc;
    rvfi_insn <= mw_instruction;
    rvfi_rd_addr <= mw_valid && mw_writeback ? mw_rd : 5'b0;
    rvfi_rd_wdata <= mw_rd == 5'd0 ? 32'b0 : w_data;

    rvfi_em_csr_marchid_rmask <= de_valid && de_read_csr && de_immed[15:0] == CSR_MARCHID ? 32'hffffffff : 32'h00000000;
    rvfi_em_csr_marchid_rdata <= e_csr_val;
    rvfi_mw_csr_marchid_rmask <= rvfi_em_csr_marchid_rmask;
    rvfi_mw_csr_marchid_rdata <= rvfi_em_csr_marchid_rdata;
    rvfi_csr_marchid_rmask <= rvfi_mw_csr_marchid_rmask;
    rvfi_csr_marchid_rdata <= rvfi_mw_csr_marchid_rdata;

    rvfi_em_csr_mscratch_rmask <= de_valid && de_read_csr && de_immed[15:0] == CSR_MSCRATCH ? 32'hffffffff : 32'h00000000;
    rvfi_em_csr_mscratch_rdata <= e_csr_val;
    rvfi_mw_csr_mscratch_rmask <= rvfi_em_csr_mscratch_rmask;
    rvfi_mw_csr_mscratch_rdata <= rvfi_em_csr_mscratch_rdata;
    rvfi_csr_mscratch_rmask <= rvfi_mw_csr_mscratch_rmask;
    rvfi_csr_mscratch_rdata <= rvfi_mw_csr_mscratch_rdata;
    rvfi_csr_mscratch_wmask <= mw_valid && mw_write_csr && mw_csr_rd == CSR_MSCRATCH ? 32'hffffffff : 32'h0;
    rvfi_csr_mscratch_wdata <= mw_csr_wdata;

    rvfi_em_csr_mtvec_rmask <= de_valid && de_read_csr && de_immed[15:0] == CSR_MTVEC ? 32'hffffffff : 32'h00000000;
    rvfi_em_csr_mtvec_rdata <= e_csr_val;
    rvfi_mw_csr_mtvec_rmask <= rvfi_em_csr_mtvec_rmask;
    rvfi_mw_csr_mtvec_rdata <= rvfi_em_csr_mtvec_rdata;
    rvfi_csr_mtvec_rmask <= w_exception ? 32'hffffffff : rvfi_mw_csr_mtvec_rmask;
    rvfi_csr_mtvec_rdata <= w_exception ? mtvec_reg : rvfi_mw_csr_mtvec_rdata;
    rvfi_csr_mtvec_wmask <= mw_valid && mw_write_csr && mw_csr_rd == CSR_MTVEC ? 32'hffffffff : 32'h0;
    rvfi_csr_mtvec_wdata <= mw_csr_wdata;

    rvfi_em_csr_mcause_rmask <= de_valid && de_read_csr && de_immed[15:0] == CSR_MCAUSE ? 32'hffffffff : 32'h00000000;
    rvfi_em_csr_mcause_rdata <= e_csr_val;
    rvfi_mw_csr_mcause_rmask <= rvfi_em_csr_mcause_rmask;
    rvfi_mw_csr_mcause_rdata <= rvfi_em_csr_mcause_rdata;
    rvfi_csr_mcause_rmask <= rvfi_mw_csr_mcause_rmask;
    rvfi_csr_mcause_rdata <= rvfi_mw_csr_mcause_rdata;
    rvfi_csr_mcause_wmask <= (mw_valid && mw_write_csr && mw_csr_rd == CSR_MCAUSE) || w_exception ? 32'hffffffff : 32'h0;
    rvfi_csr_mcause_wdata <= w_exception ? {w_mcause_i, 27'b0, w_mcause_code} : mw_csr_wdata;

    rvfi_em_csr_mtval_rmask <= de_valid && de_read_csr && de_immed[15:0] == CSR_MTVAL ? 32'hffffffff : 32'h00000000;
    rvfi_em_csr_mtval_rdata <= e_csr_val;
    rvfi_mw_csr_mtval_rmask <= rvfi_em_csr_mtval_rmask;
    rvfi_mw_csr_mtval_rdata <= rvfi_em_csr_mtval_rdata;
    rvfi_csr_mtval_rmask <= rvfi_mw_csr_mtval_rmask;
    rvfi_csr_mtval_rdata <= rvfi_mw_csr_mtval_rdata;
    rvfi_csr_mtval_wmask <= (mw_valid && mw_write_csr && mw_csr_rd == CSR_MTVAL) || w_exception ? 32'hffffffff : 32'h0;
    rvfi_csr_mtval_wdata <= w_exception ? w_mtval : mw_csr_wdata;

    rvfi_em_csr_mepc_rmask <= de_valid && de_read_csr && de_immed[15:0] == CSR_MEPC ? 32'hffffffff : 32'h00000000;
    rvfi_em_csr_mepc_rdata <= e_csr_val;
    rvfi_mw_csr_mepc_rmask <= rvfi_em_csr_mepc_rmask;
    rvfi_mw_csr_mepc_rdata <= rvfi_em_csr_mepc_rdata;
    rvfi_csr_mepc_rmask <= rvfi_mw_csr_mepc_rmask;
    rvfi_csr_mepc_rdata <= rvfi_mw_csr_mepc_rdata;
    rvfi_csr_mepc_wmask <= (mw_valid && mw_write_csr && mw_csr_rd == CSR_MEPC) || w_exception ? 32'hffffffff : 32'h0;
    rvfi_csr_mepc_wdata <= w_exception ? mw_pc : mw_csr_wdata;
end

`ifdef verilator
export "DPI-C" function write_csr;

function void write_csr;
    input int csr;
    input int val;

    case (csr[15:0])
    CSR_MTVEC: {mtvec_reg_base, mtvec_reg_mode} = {val[31:2], val[0]};
    default: $display("unsupported CSR %x", csr);
    endcase
endfunction
`endif // verilator

endmodule