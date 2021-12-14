`default_nettype none

import RXVTypes::num_phys_regs;
import RXVTypes::arch_reg_tag;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::rxv_alu_op;
import RXVTypes::rxv_csr_op;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_prediction;
import RXVTypes::rxv_uop;
import RXVTypes::b_immed;
import RXVTypes::i_immed;
import RXVTypes::j_immed;
import RXVTypes::u_immed;
import RXVTrace::trace_start_instruction;
import RXVCSR::RXVException;
import RXVCSR::MCAUSE_id;

module RXVDecode #(
    parameter int commit_order = 3
) (
    input  logic                              clk,
    input  logic                              reset,
    // From fetch
    input  logic                              decode_valid,
    input  logic          [             31:2] decode_pc,
    input  logic          [             31:2] decode_next_pc,
    input  rxv_prediction                     decode_prediction,
    input  logic          [             31:0] decode_instr,
    output logic                              decode_predict_kill,
    output logic          [             31:2] decode_predict_kill_address,
    output logic                              decode_stall,
    output logic          [             31:2] decode_resume_tgt,
    output logic                              decode_resteer,
    output logic          [             31:2] decode_resteer_tgt,
    // CSR
    input  logic                              valid_csr_in,
    output logic          [             11:0] decode_csr_addr,
    // Register write snoop
    input  phys_reg_tag                       reg_wr_addr,
    input  logic                              reg_wr_en,
    // To register allocator
    input  logic                              reg_alloc_empty,
    output logic                              reg_alloc_valid,
    input  phys_reg_tag                       allocated_reg,
    // To commit buffer
    input  logic                              commit_buffer_full,
    input  logic                              commit_buffer_empty,
    output commit_entry                       commit_dispatch,
    output logic                              commit_dispatch_valid,
    input                 [ commit_width-1:0] dispatch_id,
    // To scoreboard
    output phys_reg_tag                       busy_reg_out,
    output logic                              busy_valid_out,
    input  logic          [num_phys_regs-1:0] busy_status,
    // Scheduler
    output logic                              dispatch_int,
    input  logic                              int_ready,
    // verilator lint_off UNUSED
    // verilator lint_off UNDRIVEN
    output logic                              dispatch_lsu,
    input  logic                              lsu_ready,
    // verilator lint_on UNUSED
    // verilator lint_on UNDRIVEN
    // To renamer
    output renamed_reg                        rename_out,
    output logic                              rename_out_valid,
    input  phys_reg_tag                       stale_phys_reg,
    output arch_reg_tag                       rename_lookup_arch         [1:0],
    input  phys_reg_tag                       rename_lookup_phys         [1:0],
    // To register fetch
    output phys_reg_tag                       ra_phys,
    output phys_reg_tag                       rb_phys,
    // To exec
    output rxv_alu_op                         exec_alu_op,
    output rxv_csr_op                         exec_csr_op,
    output logic                              exec_valid,
    output logic                              exec_have_writeback,
    output phys_reg_tag                       exec_rd,
    output                [ commit_width-1:0] exec_id,
    output logic          [             31:0] exec_immed,
    output rxv_opcode                         exec_opcode,
    output rxv_uop                            exec_uop,
    output logic                              exec_bypass_rs1,
    output logic                              exec_bypass_rs2,
    // Exec branch
    output logic          [             31:2] exec_pc,
    output logic          [             31:2] exec_next_pc,
    output rxv_prediction                     exec_prediction,
    output logic          [             31:1] exec_branch_target,
    input  logic                              kill_valid,
    input  logic                              exec_resteer,
    // Exception handling
    output RXVException                       decode_exception,
    output logic          [ commit_width-1:0] decode_except_id
);

    wire [ 6:0] funct7 = decode_instr[31:25];
    wire [ 4:0] rs2 = decode_instr[24:20];
    wire [ 4:0] rs1 = decode_instr[19:15];
    wire [ 2:0] funct3 = decode_instr[14:12];
    wire [11:7] rd = decode_instr[11:7];
    // verilator lint_off UNUSED
    wire [ 6:0] opcode = decode_instr[6:0];
    // verilator lint_on UNUSED

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic                                rs1_busy;
    logic                                rs2_busy;
    logic                                src_regs_ready;
    logic                                illegal_instruction;
    logic                                illegal_opcode;
    logic                                int_bypass_valid;
    logic                                have_rs1;
    logic                                have_rs2;
    arch_reg_tag                         last_rd_arch;
    logic                                system_stall;
    RXVException                         decode_exception_next;
    logic        [     commit_width-1:0] decode_except_id_next;

    logic                                is_branch;

    logic        [$bits(rxv_alu_op)-1:0] exec_alu_op_next;
    logic                                exec_valid_next;
    logic                                exec_have_writeback_next;
    logic        [                 31:0] exec_immed_next;
    logic        [                 31:0] exec_branch_target_next;
    logic        [   $bits(rxv_uop)-1:0] exec_uop_next;
    logic                                exec_bypass_rs1_next;
    logic                                exec_bypass_rs2_next;

    logic                                opc_op;
    rxv_alu_op                           op_alu_op;
    logic                                op_illegal_instr;
    rxv_uop                              op_uop;

    logic                                opc_imm;
    rxv_alu_op                           imm_alu_op;
    logic                                imm_illegal_instr;
    rxv_uop                              imm_uop;

    logic                                opc_branch;
    rxv_alu_op                           branch_alu_op;
    logic                                branch_illegal_instr;
    logic        [                 31:0] branch_target;
    rxv_uop                              branch_uop;

    logic                                opc_jal;
    logic        [                 31:0] jal_target;
    rxv_uop                              jal_uop;

    logic                                opc_jalr;
    rxv_alu_op                           jalr_alu_op;
    rxv_uop                              jalr_uop;

    logic                                opc_lui;
    rxv_uop                              lui_uop;

    logic                                opc_auipc;
    rxv_uop                              auipc_uop;

    logic                                opc_system;
    rxv_csr_op                           csr_op_next;
    logic                                system_illegal_instr;
    rxv_uop                              system_uop;
    logic                                system_have_writeback;

    logic                                opc_misc_mem;
    logic                                misc_mem_illegal_instr;
    rxv_uop                              misc_mem_uop;

    always_comb begin
        opc_op          = 1'b0;
        opc_imm         = 1'b0;
        opc_branch      = 1'b0;
        opc_jal         = 1'b0;
        opc_jalr        = 1'b0;
        opc_lui         = 1'b0;
        opc_auipc       = 1'b0;
        opc_system      = 1'b0;
        opc_misc_mem    = 1'b0;
        exec_immed_next = 'b0;
        is_branch       = 1'b0;
        have_rs1        = 1'b0;
        have_rs2        = 1'b0;
        illegal_opcode = 1'b0;

        unique case (opcode[6:2])
            RXVTypes::OPC_OP: begin
                opc_op   = 1'b1;
                have_rs1 = 1'b1;
                have_rs2 = 1'b1;
            end
            RXVTypes::OPC_IMM: begin
                opc_imm         = 1'b1;
                have_rs1        = 1'b1;
                exec_immed_next = i_immed(decode_instr);
            end
            RXVTypes::OPC_BRANCH: begin
                opc_branch = 1'b1;
                is_branch  = 1'b1;
                have_rs1   = 1'b1;
                have_rs2   = 1'b1;
            end
            RXVTypes::OPC_JAL: begin
                opc_jal   = 1'b1;
                is_branch = 1'b1;
            end
            RXVTypes::OPC_JALR: begin
                opc_jalr        = 1'b1;
                is_branch       = 1'b1;
                have_rs1        = 1'b1;
                exec_immed_next = i_immed(decode_instr);
            end
            RXVTypes::OPC_LUI: begin
                opc_lui         = 1'b1;
                exec_immed_next = u_immed(decode_instr);
            end
            RXVTypes::OPC_AUIPC: begin
                opc_auipc       = 1'b1;
                exec_immed_next = u_immed(decode_instr);
            end
            RXVTypes::OPC_SYSTEM: begin
                opc_system      = 1'b1;
                exec_immed_next = u_immed(decode_instr);
                // Only CSRRW/CSRRS/CSRRC have a source register
                have_rs1        = funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b011;
            end
            RXVTypes::OPC_MISC_MEM: begin
                opc_misc_mem   = 1'b1;
            end
            default: illegal_opcode = 1'b1;
        endcase

        if (decode_instr[1:0] != 2'b11) illegal_opcode = 1'b1;
    end

    always_comb begin
        decode_predict_kill         = decode_valid & decode_prediction.predicted & ~is_branch;
        decode_predict_kill_address = decode_pc;
        decode_resteer              = decode_valid & decode_prediction.predicted & ~is_branch;
        decode_resteer_tgt          = decode_next_pc;
    end

    always_comb begin
        op_illegal_instr = 1'b0;
        op_alu_op        = RXVTypes::ALU_ADD;
        op_uop           = RXVTypes::UOP_ALU;

        unique case ({
            funct7, funct3
        })
            10'b0000000_000: op_alu_op = RXVTypes::ALU_ADD;
            10'b0100000_000: op_alu_op = RXVTypes::ALU_SUB;
            10'b0000000_001: op_alu_op = RXVTypes::ALU_SLL;
            10'b0000000_010: op_alu_op = RXVTypes::ALU_SLT;
            10'b0000000_011: op_alu_op = RXVTypes::ALU_SLTU;
            10'b0000000_100: op_alu_op = RXVTypes::ALU_XOR;
            10'b0000000_101: op_alu_op = RXVTypes::ALU_SLR;
            10'b0100000_101: op_alu_op = RXVTypes::ALU_SRA;
            10'b0000000_110: op_alu_op = RXVTypes::ALU_OR;
            10'b0000000_111: op_alu_op = RXVTypes::ALU_AND;
            default: op_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        imm_illegal_instr = 1'b0;
        imm_alu_op        = RXVTypes::ALU_ADD;
        imm_uop           = RXVTypes::UOP_ALU;

        unique casez ({
            funct7, funct3
        })
            10'bzzzzzzz_000: imm_alu_op = RXVTypes::ALU_ADD;
            10'bzzzzzzz_010: imm_alu_op = RXVTypes::ALU_SLT;
            10'bzzzzzzz_011: imm_alu_op = RXVTypes::ALU_SLTU;
            10'bzzzzzzz_100: imm_alu_op = RXVTypes::ALU_XOR;
            10'bzzzzzzz_110: imm_alu_op = RXVTypes::ALU_OR;
            10'bzzzzzzz_111: imm_alu_op = RXVTypes::ALU_AND;
            10'b0000000_001: imm_alu_op = RXVTypes::ALU_SLL;
            10'b0000000_101: imm_alu_op = RXVTypes::ALU_SLR;
            10'b0100000_101: imm_alu_op = RXVTypes::ALU_SRA;
            default: imm_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        branch_illegal_instr = 1'b0;
        branch_alu_op        = RXVTypes::ALU_ADD;
        branch_uop           = RXVTypes::UOP_ALU;

        unique case (funct3)
            3'b000: begin
                branch_alu_op = RXVTypes::ALU_SUB;
                branch_uop    = RXVTypes::UOP_BEQ;
            end  // BEQ
            3'b001: begin
                branch_alu_op = RXVTypes::ALU_SUB;
                branch_uop    = RXVTypes::UOP_BNE;
            end  // BNE
            3'b100: begin
                branch_alu_op = RXVTypes::ALU_SLT;
                branch_uop    = RXVTypes::UOP_BLT;
            end  // BLT
            3'b101: begin
                branch_alu_op = RXVTypes::ALU_SLT;
                branch_uop    = RXVTypes::UOP_BGE;
            end  // BGE
            3'b110: begin
                branch_alu_op = RXVTypes::ALU_SLTU;
                branch_uop    = RXVTypes::UOP_BLT;
            end  // BLTU
            3'b111: begin
                branch_alu_op = RXVTypes::ALU_SLTU;
                branch_uop    = RXVTypes::UOP_BGE;
            end  // BGEU
            default: branch_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        jal_uop = RXVTypes::UOP_JAL;
    end

    always_comb begin
        jalr_alu_op = RXVTypes::ALU_ADD;
        jalr_uop    = RXVTypes::UOP_JALR;
    end

    always_comb begin
        lui_uop = RXVTypes::UOP_LUI;
    end

    always_comb begin
        auipc_uop = RXVTypes::UOP_AUIPC;
    end

    always_comb begin
        misc_mem_uop = RXVTypes::UOP_ALU;

        unique casez (decode_instr)
            32'b0000_zzzz_zzzz_0000_0000_0000_0000_1111: begin  // FENCE
                misc_mem_uop           = RXVTypes::UOP_ALU;
                misc_mem_illegal_instr = 1'b0;
            end
            default: misc_mem_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        system_illegal_instr  = 1'b0;
        csr_op_next           = RXVTypes::CSR_SWAP;
        system_uop            = RXVTypes::UOP_ALU;
        system_have_writeback = 1'b0;

        unique case (funct3)
            3'b000: begin
                unique casez (decode_instr)
                    32'b0000_0000_0000_0000_0000_0000_0111_0011: begin  // ECALL
                        system_uop           = RXVTypes::UOP_ECALL;
                        system_illegal_instr = 1'b0;
                    end
                    32'b0000_0000_0001_0000_0000_0000_0111_0011: begin  // EBREAK
                        system_uop           = RXVTypes::UOP_EBREAK;
                        system_illegal_instr = 1'b0;
                    end
                    32'b0011_0000_0010_0000_0000_0000_0111_0011: begin  // MRET
                        system_uop           = RXVTypes::UOP_MRET;
                        system_illegal_instr = 1'b0;
                    end
                    32'b0001_0000_0101_0000_0000_0000_0111_0011: begin  // WFI
                        system_illegal_instr = 1'b0;
                    end
                    default: system_illegal_instr = 1'b1;
                endcase
            end
            3'b001: begin  // CSRRW
                system_uop            = RXVTypes::UOP_CSR;
                csr_op_next           = RXVTypes::CSR_SWAP;
                system_have_writeback = 1'b1;
                system_illegal_instr  = ~valid_csr_in;
            end
            3'b010: begin  // CSRRS
                system_uop            = RXVTypes::UOP_CSR;
                csr_op_next           = ~|rs1 ? RXVTypes::CSR_READ : RXVTypes::CSR_SET;
                system_have_writeback = 1'b1;
                system_illegal_instr  = ~valid_csr_in;
            end
            3'b011: begin  // CSRRC
                system_uop            = RXVTypes::UOP_CSR;
                csr_op_next           = ~|rs1 ? RXVTypes::CSR_READ : RXVTypes::CSR_CLEAR;
                system_have_writeback = 1'b1;
                system_illegal_instr  = ~valid_csr_in;
            end
            3'b101: begin  // CSRRWI
                system_uop            = RXVTypes::UOP_CSRI;
                csr_op_next           = RXVTypes::CSR_SWAP;
                system_have_writeback = 1'b1;
                system_illegal_instr  = ~valid_csr_in;
            end
            3'b110: begin  // CSRRSI
                system_uop = RXVTypes::UOP_CSRI;
                csr_op_next = ~|decode_instr[19:15] ? RXVTypes::CSR_READ : RXVTypes::CSR_SET;
                system_have_writeback = 1'b1;
                system_illegal_instr = ~valid_csr_in;
            end
            3'b111: begin  // CSRRCI
                system_uop = RXVTypes::UOP_CSRI;
                csr_op_next = ~|decode_instr[19:15] ? RXVTypes::CSR_READ : RXVTypes::CSR_CLEAR;
                system_have_writeback = 1'b1;
                system_illegal_instr = ~valid_csr_in;
            end
            default: system_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        exec_alu_op_next = 'b0;
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_op}} & op_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_imm}} & imm_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_branch}} & branch_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_jalr}} & jalr_alu_op);
    end

    always_comb begin
        branch_target = {decode_pc, 2'b0} + b_immed(decode_instr);
    end

    always_comb begin
        jal_target = {decode_pc, 2'b0} + j_immed(decode_instr);
    end

    always_comb begin
        exec_branch_target_next = 32'b0;
        exec_branch_target_next |= {32{opc_branch}} & branch_target;
        exec_branch_target_next |= {32{opc_jal}} & jal_target;
    end

    always_comb begin
        exec_have_writeback_next = 1'b0;
        exec_have_writeback_next |= opc_op & ~op_illegal_instr;
        exec_have_writeback_next |= opc_imm & ~imm_illegal_instr;
        exec_have_writeback_next |= opc_jal;
        exec_have_writeback_next |= opc_jalr;
        exec_have_writeback_next |= opc_lui;
        exec_have_writeback_next |= opc_auipc;
        exec_have_writeback_next |= opc_system & system_have_writeback;

        if (~|rd) exec_have_writeback_next = 1'b0;
    end

    always_comb begin
        exec_uop_next = 'b0;
        exec_uop_next |= ({$bits(rxv_uop) {opc_op}} & op_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_imm}} & imm_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_branch}} & branch_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_jal}} & jal_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_jalr}} & jalr_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_lui}} & lui_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_auipc}} & auipc_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_system}} & system_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_misc_mem}} & misc_mem_uop);
    end

    always_comb begin
        illegal_instruction = (opc_op & op_illegal_instr) |
            (opc_imm & imm_illegal_instr) |
            (opc_branch & branch_illegal_instr) |
            (opc_system & system_illegal_instr) |
            (opc_misc_mem & misc_mem_illegal_instr) |
            illegal_opcode;
    end

    always_comb begin
        system_stall = opcode[6:2] == RXVTypes::OPC_SYSTEM && ~commit_buffer_empty;
    end

    always_comb begin
        decode_stall      = decode_valid & (reg_alloc_empty | commit_buffer_full | ~src_regs_ready | system_stall);
        decode_resume_tgt = decode_pc;
    end

    always_comb begin
        exec_valid_next =
            !illegal_instruction && decode_valid && !decode_stall &&
            !kill_valid && !exec_resteer && int_ready;
    end

    always_comb begin
        rename_lookup_arch[0] = rs1;
        rename_lookup_arch[1] = rs2;
    end

    always_comb begin
        int_bypass_valid = exec_valid && exec_have_writeback &&
            (exec_uop == RXVTypes::UOP_ALU || exec_uop == RXVTypes::UOP_AUIPC ||
             exec_uop == RXVTypes::UOP_LUI);
    end

    always_comb begin
        exec_bypass_rs1_next = int_bypass_valid && last_rd_arch == rs1;
        exec_bypass_rs2_next = int_bypass_valid && last_rd_arch == rs2;
    end

    always_comb begin
        rs1_busy = busy_status[rename_lookup_phys[0]];
        if (reg_wr_en && reg_wr_addr == rename_lookup_phys[0]) rs1_busy = 1'b0;
        if (exec_bypass_rs1_next) rs1_busy = 1'b0;
    end

    always_comb begin
        rs2_busy = busy_status[rename_lookup_phys[1]];
        if (reg_wr_en && reg_wr_addr == rename_lookup_phys[1]) rs2_busy = 1'b0;
        if (exec_bypass_rs2_next) rs2_busy = 1'b0;
    end

    always_comb begin
        src_regs_ready = ~((have_rs1 & rs1_busy) | (have_rs2 & rs2_busy));
    end

    always_comb begin
        commit_dispatch.stale_phys = stale_phys_reg;
        commit_dispatch.dest_reg = rename_out;
        commit_dispatch.pc = decode_pc;
        commit_dispatch.have_writeback = exec_have_writeback_next;

        commit_dispatch_valid = ~kill_valid & (exec_valid_next | (decode_valid & illegal_instruction));
    end

    always_comb begin
        rename_out.arch  = rd;
        rename_out.phys  = allocated_reg;

        rename_out_valid = exec_valid_next & |rd & exec_have_writeback_next;
    end

    always_comb begin
        busy_reg_out   = rename_out.phys;
        busy_valid_out = exec_valid_next & |rd & exec_have_writeback_next;
    end

    always_comb begin
        reg_alloc_valid = exec_valid_next & |rd & exec_have_writeback_next;
    end

    always_comb begin
        ra_phys = rename_lookup_phys[0];
        rb_phys = rename_lookup_phys[1];
    end

    always_comb begin
        decode_csr_addr = decode_instr[31:20];
    end

    always_comb begin
        decode_exception_next.pc = decode_pc;
        decode_exception_next.val = decode_instr;
        decode_exception_next.cause = RXVCSR::MCAUSE_ILLEGAL_INSTR;
        decode_exception_next.valid = ~kill_valid & ~exec_resteer & ~commit_buffer_full & decode_valid & illegal_instruction;
    end

    always_comb begin
        decode_except_id_next = dispatch_id;
    end

    RXVDFF #(
        .width($bits(exec_alu_op))
    ) exec_alu_op_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_alu_op_next),
        .q    (exec_alu_op)
    );

    RXVDFF #(
        .width($bits(exec_csr_op))
    ) exec_csr_op_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (csr_op_next),
        .q    (exec_csr_op)
    );

    RXVDFF #(
        .width($bits(phys_reg_tag))
    ) exec_rd_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (allocated_reg),
        .q    (exec_rd)
    );

    RXVDFF #(
        .width(commit_width)
    ) exec_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dispatch_id),
        .q    (exec_id)
    );

    RXVDFF exec_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_valid_next),
        .q    (exec_valid)
    );

    RXVDFF exec_have_writeback_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_have_writeback_next),
        .q    (exec_have_writeback)
    );

    RXVDFF #(
        .width(32)
    ) exec_immed_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_immed_next),
        .q    (exec_immed)
    );

    RXVDFF #(
        .width($bits(RXVTypes::rxv_opcode))
    ) exec_opcode_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (opcode[6:2]),
        .q    (exec_opcode)
    );

    RXVDFF #(
        .width($bits(RXVTypes::rxv_prediction))
    ) exec_prediction_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (decode_prediction),
        .q    (exec_prediction)
    );

    RXVDFF #(
        .width(30)
    ) exec_pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (decode_pc),
        .q    (exec_pc)
    );

    RXVDFF #(
        .width(30)
    ) exec_next_pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (decode_next_pc),
        .q    (exec_next_pc)
    );

    RXVDFF #(
        .width(31)
    ) exec_branch_target_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_branch_target_next[31:1]),
        .q    (exec_branch_target)
    );

    RXVDFF #(
        .width($bits(RXVTypes::rxv_uop))
    ) exec_uop_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_uop_next),
        .q    (exec_uop)
    );

    RXVDFF #(
        .width($bits(RXVTypes::arch_reg_tag))
    ) last_rd_arch_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd),
        .q    (last_rd_arch)
    );

    RXVDFF exec_bypass_rs1_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_bypass_rs1_next),
        .q    (exec_bypass_rs1)
    );

    RXVDFF exec_bypass_rs2_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_bypass_rs2_next),
        .q    (exec_bypass_rs2)
    );

    RXVDFF #(
        .width($bits(RXVCSR::RXVException))
    ) decode_exception_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (decode_exception_next),
        .q    (decode_exception)
    );

    RXVDFF #(
        .width($bits(decode_except_id))
    ) decode_except_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (decode_except_id_next),
        .q    (decode_except_id)
    );

    always_ff @(posedge clk) begin
        if (decode_valid && !decode_stall && !kill_valid && !exec_resteer) begin
            trace_start_instruction(32'(dispatch_id), decode_pc, decode_instr, 2'b11);
        end
        if (decode_valid && decode_exception_next.valid) begin
            trace_start_instruction(32'(dispatch_id), decode_pc, decode_instr, 2'b11);
        end
    end

endmodule
