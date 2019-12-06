`ifdef verilator
`define RXV_RVFI
`endif

module RXVCore(
    input logic clk,
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

`include "RiscVDefines.svh"

wire d_write_pc;
wire e_write_pc;
wire f_write_pc           = w_write_pc | e_write_pc | d_write_pc;
wire [31:0] f_write_pc_val = w_write_pc ? w_next_pc :
                           e_write_pc ? e_next_pc :
                           d_br_tgt;

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

wire [31:0] instruction;
`ifdef RXV_RVFI
wire fd_intr;
`endif
wire [31:0] fd_pc;
wire fd_valid;

RXVFetch RXVFetch(
    .clk(clk),
    .reset(reset),
    .i_addr(i_addr),
    .i_data(i_data),
    .instruction(instruction),
`ifdef RXV_RVFI
    .fd_intr(fd_intr),
`endif
    .fd_pc(fd_pc),
    .fd_valid(fd_valid),
    .wf_finish_flush(wf_finish_flush),
    .w_exception(w_exception),
    .df_flush(df_flush),
    .f_write_pc(f_write_pc),
    .f_write_pc_val(f_write_pc_val),
    .w_take_interrupt(w_take_interrupt),
    .d_load_delay(d_load_delay)
);

wire [31:0] de_immed;
wire [31:0] de_pc;
wire [31:0] de_next_seq_pc;
wire [31:0] de_branch_tgt;
wire [4:0] de_rd;
wire de_writeback;
wire de_illegal_instr;
wire [31:0] de_instruction;
wire de_valid;
wire [1:0] de_br_type;
wire [2:0] de_funct3;
wire de_load;
wire de_store;
wire [1:0] de_ls_width;
wire de_load_sext;
`ifdef RXV_RVFI
wire de_read_csr;
wire de_intr;
`endif
wire de_write_csr;
wire [4:0] de_csr_immed;
wire de_do_mret;
wire de_do_ecall;
wire de_do_ebreak;
wire de_do_fence;
wire [3:0] de_alu_op;
wire de_op2_immed;
wire [31:0] d_br_tgt;
wire fwd_rs1_e, fwd_rs2_e;
reg fwd_rs1_m, fwd_rs2_m;
wire df_flush;
wire [4:0] rs1;
wire [4:0] rs2;
wire d_load_delay;
wire [31:0] de_csr_val;

RXVDecode RXVDecode(
    .clk(clk),
    .reset(reset),
    .fd_pc(fd_pc),
    .fd_valid(fd_valid),
    .w_exception(w_exception),
    .e_instr_ac(e_instr_ac),
    .m_abort(m_abort),
    .instruction(instruction),
    .mscratch_reg(mscratch_reg),
    .mcause_reg(mcause_reg),
    .mtval_reg(mtval_reg),
    .mtvec_reg(mtvec_reg),
    .mip_reg(mip_reg),
    .mie_reg(mie_reg),
    .mcounteren_reg(mcounteren_reg),
    .mstatus_reg(mstatus_reg),
    .mepc_reg(mepc_reg),
    .mcycle_reg(mcycle_reg),
    .minstret_reg(minstret_reg),
    .de_csr_val(de_csr_val),
    .de_immed(de_immed),
    .de_pc(de_pc),
    .de_next_seq_pc(de_next_seq_pc),
    .de_branch_tgt(de_branch_tgt),
    .de_rd(de_rd),
    .de_writeback(de_writeback),
    .de_illegal_instr(de_illegal_instr),
    .de_instruction(de_instruction),
    .de_valid(de_valid),
    .de_br_type(de_br_type),
    .de_funct3(de_funct3),
    .de_load(de_load),
    .de_store(de_store),
    .de_ls_width(de_ls_width),
    .de_load_sext(de_load_sext),
`ifdef RXV_RVFI
    .fd_intr(fd_intr),
    .de_read_csr(de_read_csr),
    .de_intr(de_intr),
`endif
    .de_write_csr(de_write_csr),
    .de_csr_immed(de_csr_immed),
    .de_do_mret(de_do_mret),
    .de_do_ecall(de_do_ecall),
    .de_do_ebreak(de_do_ebreak),
    .de_do_fence(de_do_fence),
    .de_alu_op(de_alu_op),
    .de_op2_immed(de_op2_immed),
    .d_write_pc(d_write_pc),
    .d_br_tgt(d_br_tgt),
    .df_flush(df_flush),
    .fwd_rs1_e(fwd_rs1_e),
    .fwd_rs2_e(fwd_rs2_e),
    .rs1(rs1),
    .rs2(rs2),
    .d_load_delay(d_load_delay)
);

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

wire em_writeback;
wire [4:0] em_rd;
wire [31:0] em_result;
wire [31:0] em_pc;
wire [31:0] em_next_pc;
wire [31:0] em_instruction;
wire [31:0] em_store_data;
wire em_illegal_instr;
wire em_valid;
wire em_load;
wire em_store;
wire [1:0] em_ls_width;
wire [15:0] em_csr_rd;
wire em_load_sext;
wire em_write_csr;
wire [31:0] em_csr_wdata;
wire em_instr_align_check;
wire em_do_ecall;
wire em_do_ebreak;
wire em_do_fence;
wire em_do_mret;
`ifdef RXV_RVFI
wire em_intr;
`endif
wire [31:0] e_next_pc;
wire e_instr_ac;

RXVExec RXVExec(
    .clk(clk),
    .reset(reset),
    .rs1_data(rs1_fwd),
    .rs2_data(rs2_fwd),
    .e_write_pc(e_write_pc),
    .e_next_pc(e_next_pc),
    .em_writeback(em_writeback),
    .em_rd(em_rd),
    .em_result(em_result),
    .em_pc(em_pc),
    .em_next_pc(em_next_pc),
    .em_instruction(em_instruction),
    .em_store_data(em_store_data),
    .em_illegal_instr(em_illegal_instr),
    .em_valid(em_valid),
    .em_load(em_load),
    .em_store(em_store),
    .em_ls_width(em_ls_width),
    .em_csr_rd(em_csr_rd),
    .em_load_sext(em_load_sext),
    .em_write_csr(em_write_csr),
    .em_csr_wdata(em_csr_wdata),
    .em_instr_align_check(em_instr_align_check),
    .em_do_ecall(em_do_ecall),
    .em_do_ebreak(em_do_ebreak),
    .em_do_fence(em_do_fence),
    .em_do_mret(em_do_mret),
    .e_instr_ac(e_instr_ac),
    .fwd_rs1_m(fwd_rs1_m),
    .fwd_rs2_m(fwd_rs2_m),
    .de_csr_val(de_csr_val),
    .de_alu_op(de_alu_op),
    .de_immed(de_immed),
    .de_next_seq_pc(de_next_seq_pc),
    .de_br_type(de_br_type),
    .de_branch_tgt(de_branch_tgt),
    .de_funct3(de_funct3),
    .de_op2_immed(de_op2_immed),
    .de_do_mret(de_do_mret),
    .de_csr_immed(de_csr_immed),
    .de_valid(de_valid),
    .de_rd(de_rd),
    .de_pc(de_pc),
    .de_instruction(de_instruction),
    .de_illegal_instr(de_illegal_instr),
    .de_load(de_load),
    .de_store(de_store),
    .de_ls_width(de_ls_width),
    .de_load_sext(de_load_sext),
    .de_write_csr(de_write_csr),
    .de_do_ecall(de_do_ecall),
    .de_do_ebreak(de_do_ebreak),
    .de_do_fence(de_do_fence),
    .de_writeback(de_writeback),
    .rs1(rs1),
    .rs2(rs2),
    .w_exception(w_exception),
`ifdef RXV_RVFI
    .de_intr(de_intr),
    .em_intr(em_intr),
`endif
    .m_abort(m_abort)
);

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
            32'hffffffff : 32'h00000000, mscratch_reg};
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
            32'hffffffff : 32'h00000000, mcause_reg};
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
            32'hffffffff : 32'h00000000, mtvec_reg};
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
            32'hffffffff : 32'h00000000, mepc_reg};
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
            32'hffffffff : 32'h00000000, mtval_reg};
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
            32'h00000888 : 32'h00000000, mip_reg};
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
            32'h00000888 : 32'h00000000, mie_reg};
        {rvfi_csr_mie_rmask, rvfi_csr_mie_rdata} <= rvfi_csr_mie_pipe[127:64];
`endif
    end

`ifdef RXV_RVFI
wire csr_mstatus_w = mw_valid && mw_write_csr && mw_csr_rd == CSR_MSTATUS;
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
            32'h00001808 : 32'h00000000, mstatus_reg};
        {rvfi_csr_mstatus_rmask, rvfi_csr_mstatus_rdata} <= rvfi_csr_mstatus_pipe[127:64];
`endif
    end

RegFile RegFile(
    .clk(clk),
    .reset(reset),
    .rd_addr_a(rs1),
    .rd_data_a(rs1_data),
    .rd_addr_b(rs2),
    .rd_data_b(rs2_data),
    .wr_en(w_wr_en),
    .wr_addr(mw_rd),
    .wr_data(w_data)
);

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


wire wf_finish_flush    = (mw_valid & mw_write_csr) |
                          (mw_valid & mw_do_fence) |
                          (mw_valid & mw_do_mret) |
                          w_exception;

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
    rvfi_csr_marchid_pipe <= {rvfi_csr_marchid_pipe[63:0], de_valid && de_read_csr && de_immed[15:0] == CSR_MARCHID ? 32'hffffffff : 32'h00000000, RXV_MARCHID};
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

    RXVFetch.reset_vector = val;
endfunction

function void write_pc;
    input int val;

    RXVFetch.pc = val;
endfunction

`endif // verilator
`endif // RXV_RVFI

endmodule
