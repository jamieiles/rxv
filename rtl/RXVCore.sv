// verilator lint_off UNUSED
// verilator lint_off UNDRIVEN
module RXVCore(input logic clk,
               input logic reset,
               // Instruction bus
               output logic [31:0] i_addr,
               input logic [31:0] i_data,
               // RVFI
               output logic rvfi_valid,
               output logic [31:0] rvfi_insn,
               output logic [4:0] rvfi_rd_addr,
               output logic [31:0] rvfi_rd_wdata,
               output logic [31:0] rvfi_pc_rdata,
               output logic [31:0] rvfi_pc_wdata);

wire [31:0] instruction = i_data;

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
                          d_opcode == OPC_ARITH;

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
                           (funct3 == 3'd5 && ~|{funct7[6], funct7[5:0]}));
wire d_bad_arith        = d_opcode == OPC_ARITH &&
                          ((funct3 == 3'd0 || funct7 == 7'd5) && ~|{funct7[6], funct7[5:0]});
wire d_bad_env          = d_opcode == OPC_ENV &&
                          (funct3 == 3'd4 ||
                           !(instruction == INSTR_ECALL ||
                             instruction == INSTR_EBREAK ||
                             instruction == INSTR_MRET));
wire d_illegal_instr    = d_bad_opc | d_bad_branch | d_bad_load | d_bad_store |
                          d_bad_arithi | d_bad_arith | d_bad_env;
wire [1:0] d_br_type    = d_opcode == OPC_JAL ? BRANCH_IMMED :
                          d_opcode == OPC_JALR ? BRANCH_INDIR :
                          d_opcode == OPC_BRANCH ? BRANCH_COND : BRANCH_NONE;

// Instruction execution
wire e_sub_b;
wire [31:0] e_sub;
wire [31:0] alu_out     = de_opcode == OPC_LUI ? de_immed :
                          de_opcode == OPC_AUIPC ? de_immed + de_pc :
                          de_opcode == OPC_JAL ? de_pc + 32'd4 :
                          de_opcode == OPC_JALR ? de_pc + 32'd4 :
                          de_opcode == OPC_ARITHI || de_opcode == OPC_ARITH ? e_arith_res :
                          32'b0;
wire [31:0] e_indir_tgt = rs1_fwd + de_immed;
wire [31:0] e_next_pc   = de_br_type == BRANCH_IMMED ? de_pc + de_immed :
                          de_br_type == BRANCH_INDIR ? {e_indir_tgt[31:1], 1'b0} :
                          de_br_type == BRANCH_COND && e_br_taken ? de_pc + de_immed :
                          de_pc + 32'd4;
wire e_write_pc         = de_br_type == BRANCH_IMMED || de_br_type == BRANCH_INDIR;
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
assign {e_sub_b, e_sub} = {1'b0, rs1_fwd} - {1'b0, e_arith_op2};
wire [31:0] e_xor       = rs1_fwd ^ e_arith_op2;
wire [31:0] e_or        = rs1_fwd | e_arith_op2;
wire [31:0] e_and       = rs1_fwd & e_arith_op2;
wire [31:0] e_lt        = {31'b0, e_sub[31]};
wire [31:0] e_ltu       = {31'b0, e_sub_b};
wire [31:0] e_arith_res = de_opcode == OPC_ARITH && de_funct3 == 3'd0 && ~de_funct7[5] ? e_add :
                          de_opcode == OPC_ARITH && de_funct3 == 3'd0 &&  de_funct7[5] ? e_sub :
                          de_opcode == OPC_ARITHI && de_funct3 == 3'd0 ? e_add :
                          de_funct3 == 3'd1 ? e_sll :
                          de_funct3 == 3'd2 ? e_lt :
                          de_funct3 == 3'd3 ? e_ltu :
                          de_funct3 == 3'd4 ? e_xor :
                          de_funct3 == 3'd5 && ~de_funct7[5] ? e_srl :
                          de_funct3 == 3'd5 &&  de_funct7[5] ? e_sra :
                          de_funct3 == 3'd6 ? e_or :
                          de_funct3 == 3'd7 ? e_and :
                          32'b0;

reg [31:0] pc;
wire [31:0] next_pc     = ef_write_pc ? em_next_pc : pc + 32'd4;
assign i_addr = pc;
wire [31:0] rs1_data, rs2_data;

wire [31:0] rs1_fwd = fwd_rs1_e ? em_result : fwd_rs1_m ? mw_result : rs1_data;
wire [31:0] rs2_fwd = fwd_rs2_e ? em_result : fwd_rs2_m ? mw_result : rs2_data;

reg fd_fetched;
reg insert_bubble;
reg ef_write_pc;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        fd_fetched <= 1'b0;
    end else begin
        if (d_is_branch) begin
            insert_bubble <= 1'b1;
        end else if (ef_write_pc) begin
            insert_bubble <= 1'b0;
        end else begin
            fd_fetched <= 1'b1;
        end
    end
end

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
reg [6:0] de_funct7;
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
        de_valid <= fd_fetched && !insert_bubble;
        de_br_type <= d_br_type;
        de_funct3 <= funct3;
        de_funct7 <= funct7;

        fwd_rs1_e <= de_valid && de_writeback && de_rd == rs1;
        fwd_rs2_e <= de_valid && de_writeback && de_rd == rs2;
    end
end

reg em_writeback;
reg [4:0] em_rd;
reg [31:0] em_result;
reg [31:0] em_pc, em_next_pc;
reg [31:0] em_instruction;
reg em_illegal_instr;
reg em_valid;

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
        em_valid <= de_valid;

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

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mw_valid <= 1'b0;
    end else begin
        mw_writeback <= em_writeback;
        mw_rd <= em_rd;
        mw_result <= em_result;
        mw_pc <= em_pc;
        mw_instruction <= em_instruction;
        mw_next_pc <= em_next_pc;
        mw_illegal_instr <= em_illegal_instr;
        mw_valid <= em_valid;
    end
end

RegFile RegFile(.rd_addr_a(rs1),
                .rd_data_a(rs1_data),
                .rd_addr_b(rs2),
                .rd_data_b(rs2_data),
                .wr_en(mw_writeback),
                .wr_addr(mw_rd),
                .wr_data(mw_result),
                .*);

always_ff @(posedge clk or posedge reset)
    if (reset)
        pc <= 32'b0;
    else begin
        pc <= next_pc;
    end

always_ff @(posedge clk) begin
    rvfi_valid <= mw_valid;
    rvfi_pc_rdata <= mw_pc;
    rvfi_pc_wdata <= mw_next_pc;
    rvfi_insn <= mw_instruction;
    rvfi_rd_addr <= mw_valid ? mw_rd : 5'b0;
    rvfi_rd_wdata <= mw_rd == 5'd0 ? 32'b0 : mw_result;
end

endmodule