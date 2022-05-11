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
import RXVTypes::s_immed;
import RXVTypes::u_immed;
import RXVTypes::commit_width;
import RXVTrace::trace_start_instruction;
import RXVTrace::trace_uop;
import RXVCSR::RXVException;
import RXVCSR::CAUSE_id;
import RXVCSR::privilege_t;
import RXVCSR::mstatus_t;

module RXVDecode (
    input  logic                              clk,
    input  logic                              reset,
    // From fetch
    input  privilege_t                        current_privilege,
    input  logic                              decode_valid,
    input  logic          [             31:2] decode_pc,
    input  logic          [             31:2] decode_next_pc,
    input  rxv_prediction                     decode_prediction,
    input  logic          [             31:0] decode_instr,
    output logic                              decode_predict_kill,
    output logic          [             31:2] decode_predict_kill_address,
    output logic                              decode_fe_stall,
    output logic                              decode_resteer,
    output logic          [             31:2] decode_resteer_tgt,
    // CSR
    input  logic                              valid_csr_in,
    output logic          [             11:0] decode_csr_addr,
    // verilator lint_off UNUSED
    input  mstatus_t                          mstatus_in,
    // verilator lint_on UNUSED
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
    output logic                              schedule_int,
    input  logic                              int_ready,
    output logic                              schedule_lsu,
    input  logic                              lsu_ready,
    output logic                              schedule_mul,
    input  logic                              mul_ready,
    output logic                              schedule_div,
    input  logic                              div_ready,
    input  logic                              lsu_busy,
    input  logic                              div_exec_busy,
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
    output logic                              int_exec_valid,
    output logic                              mul_exec_valid,
    output logic                              div_exec_valid,
    output logic                              lsu_exec_valid,
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

    typedef enum bit [1:0] {
        EXEC_PIPE_INT = 2'b00,
        EXEC_PIPE_LSU = 2'b01,
        EXEC_PIPE_MUL = 2'b10,
        EXEC_PIPE_DIV = 2'b11
    } exec_pipe_sel;

    typedef enum bit [1:0] {
        AMO_TYPE_LR,
        AMO_TYPE_SC,
        AMO_TYPE_FETCH_OP
    } amo_type;

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
    logic                                misc_mem_stall;
    RXVException                         decode_exception_next;
    logic        [     commit_width-1:0] decode_except_id_next;
    logic                                dispatch_lsu;
    logic                                dispatch_mul;
    logic                                dispatch_int;
    logic                                dispatch_div;
    logic                                decode_be_stall;

    logic                                is_branch;

    logic        [$bits(rxv_alu_op)-1:0] exec_alu_op_next;
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

    logic                                opc_mul;
    logic                                mul_illegal_instr;
    rxv_uop                              mul_uop;

    logic                                opc_div;
    logic                                div_illegal_instr;
    rxv_uop                              div_uop;

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
    logic        [                  3:0] system_exec_pipe_en;

    logic                                opc_misc_mem;
    logic                                misc_mem_illegal_instr;
    rxv_uop                              misc_mem_uop;

    logic                                opc_store;
    logic                                store_illegal_instr;
    rxv_uop                              store_uop;

    logic                                opc_load;
    logic                                load_illegal_instr;
    rxv_uop                              load_uop;

    logic                                opc_amo;
    logic                                amo_illegal_instr;
    rxv_uop                              amo_uop;
    logic                                amo_uop_wb;
    rxv_alu_op                           amo_alu_op;
    logic        [                  3:0] amo_exec_pipe_en;
    logic        [                  1:0] amo_uop_idx;
    logic        [                  1:0] amo_uop_idx_next;
    logic                                amo_alloc_tmp_reg;
    phys_reg_tag                         amo_tmp_reg;
    phys_reg_tag                         amo_tmp_reg_next;
    logic                                amo_alloc_dst_reg;
    phys_reg_tag                         amo_dst_reg;
    phys_reg_tag                         amo_dst_reg_next;
    logic        [                  2:0] amo_num_uops;
    logic                                amo_alloc_reg;
    logic                                amo_rs1_is_dst;
    logic                                amo_rs2_is_tmp;
    logic                                amo_rename_valid;
    logic                                amo_opc_valid;
    logic                                amo_complete;
    phys_reg_tag                         amo_stale_reg;
    logic        [     commit_width-1:0] amo_parent;
    logic        [     commit_width-1:0] amo_parent_next;
    amo_type                             amo_op_type;

    logic        [                  3:0] exec_pipe_en;
    logic                                dispatch_ready;

    always_comb begin
        opc_op          = 1'b0;
        opc_mul         = 1'b0;
        opc_div         = 1'b0;
        opc_imm         = 1'b0;
        opc_branch      = 1'b0;
        opc_jal         = 1'b0;
        opc_jalr        = 1'b0;
        opc_lui         = 1'b0;
        opc_auipc       = 1'b0;
        opc_system      = 1'b0;
        opc_misc_mem    = 1'b0;
        opc_amo         = 1'b0;
        exec_immed_next = 'b0;
        is_branch       = 1'b0;
        have_rs1        = 1'b0;
        have_rs2        = 1'b0;
        illegal_opcode  = 1'b0;
        opc_store       = 1'b0;
        opc_load        = 1'b0;
        exec_pipe_en    = 4'b0;

        unique case (opcode[6:2])
            RXVTypes::OPC_OP: begin
                exec_pipe_en[EXEC_PIPE_INT] = funct7 != 7'h1;
                exec_pipe_en[EXEC_PIPE_MUL] = funct7 == 7'h1 && !funct3[2];
                exec_pipe_en[EXEC_PIPE_DIV] = funct7 == 7'h1 && funct3[2];
                opc_op                      = funct7 != 7'h1;
                opc_mul                     = funct7 == 7'h1 && !funct3[2];
                opc_div                     = funct7 == 7'h1 && funct3[2];
                have_rs1                    = 1'b1;
                have_rs2                    = 1'b1;
            end
            RXVTypes::OPC_IMM: begin
                exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                opc_imm                     = 1'b1;
                have_rs1                    = 1'b1;
                exec_immed_next             = i_immed(decode_instr);
            end
            RXVTypes::OPC_BRANCH: begin
                exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                opc_branch                  = 1'b1;
                is_branch                   = 1'b1;
                have_rs1                    = 1'b1;
                have_rs2                    = 1'b1;
            end
            RXVTypes::OPC_JAL: begin
                exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                opc_jal                     = 1'b1;
                is_branch                   = 1'b1;
            end
            RXVTypes::OPC_JALR: begin
                exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                opc_jalr                    = 1'b1;
                is_branch                   = 1'b1;
                have_rs1                    = 1'b1;
                exec_immed_next             = i_immed(decode_instr);
            end
            RXVTypes::OPC_LUI: begin
                exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                opc_lui                     = 1'b1;
                exec_immed_next             = u_immed(decode_instr);
            end
            RXVTypes::OPC_AUIPC: begin
                exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                opc_auipc                   = 1'b1;
                exec_immed_next             = u_immed(decode_instr);
            end
            RXVTypes::OPC_SYSTEM: begin
                exec_pipe_en    = system_exec_pipe_en;
                opc_system      = 1'b1;
                exec_immed_next = u_immed(decode_instr);
                // Only CSRRW/CSRRS/CSRRC have a source register
                have_rs1        = (funct3 == 3'b001 || funct3 == 3'b010 || funct3 == 3'b011);

                // SFENCE.VMA has two source operands
                if (funct7 == 7'b0001001 && funct3 == 3'b000 && rd == 5'b00000) begin
                    have_rs1 = 1'b1;
                    have_rs2 = 1'b1;
                end
            end
            RXVTypes::OPC_MISC_MEM: begin
                exec_pipe_en[EXEC_PIPE_INT] = funct3 == 3'b000;  // FENCE
                exec_pipe_en[EXEC_PIPE_LSU] = funct3 == 3'b001;  // FENCE.I

                opc_misc_mem                = 1'b1;
            end
            RXVTypes::OPC_STORE: begin
                exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;
                opc_store                   = 1'b1;
                have_rs1                    = 1'b1;
                have_rs2                    = 1'b1;
                exec_immed_next             = s_immed(decode_instr);
            end
            RXVTypes::OPC_LOAD: begin
                exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;
                opc_load                    = 1'b1;
                have_rs1                    = 1'b1;
                exec_immed_next             = i_immed(decode_instr);
            end
            RXVTypes::OPC_AMO: begin
                exec_pipe_en = amo_exec_pipe_en;
                opc_amo      = 1'b1;
                have_rs1     = 1'b1;
                have_rs2     = 1'b1;
            end
            default: illegal_opcode = 1'b1;
        endcase

        if (decode_instr[1:0] != 2'b11) illegal_opcode = 1'b1;
    end

    always_comb begin
        decode_predict_kill         = decode_valid & decode_prediction.predicted & ~is_branch & ~decode_be_stall;
        decode_predict_kill_address = decode_pc;
        decode_resteer = decode_valid & decode_prediction.predicted & ~is_branch & ~decode_be_stall;
        decode_resteer_tgt = decode_next_pc;
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
        mul_illegal_instr = 1'b0;
        mul_uop           = RXVTypes::UOP_MUL;

        unique case (funct3)
            3'b000:  mul_uop = RXVTypes::UOP_MUL;
            3'b001:  mul_uop = RXVTypes::UOP_MULH;
            3'b010:  mul_uop = RXVTypes::UOP_MULHSU;
            3'b011:  mul_uop = RXVTypes::UOP_MULHU;
            default: mul_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        div_illegal_instr = 1'b0;
        div_uop           = RXVTypes::UOP_DIV;

        unique case (funct3)
            3'b100:  div_uop = RXVTypes::UOP_DIV;
            3'b101:  div_uop = RXVTypes::UOP_DIVU;
            3'b110:  div_uop = RXVTypes::UOP_REM;
            3'b111:  div_uop = RXVTypes::UOP_REMU;
            default: div_illegal_instr = 1'b1;
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
        store_illegal_instr = 1'b0;
        store_uop           = RXVTypes::UOP_SW;

        unique case (funct3)
            3'b000:  store_uop = RXVTypes::UOP_SB;
            3'b001:  store_uop = RXVTypes::UOP_SH;
            3'b010:  store_uop = RXVTypes::UOP_SW;
            default: store_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        load_illegal_instr = 1'b0;
        load_uop           = RXVTypes::UOP_LW;

        unique case (funct3)
            3'b000:  load_uop = RXVTypes::UOP_LB;
            3'b001:  load_uop = RXVTypes::UOP_LH;
            3'b010:  load_uop = RXVTypes::UOP_LW;
            3'b100:  load_uop = RXVTypes::UOP_LBU;
            3'b101:  load_uop = RXVTypes::UOP_LHU;
            default: load_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        amo_uop_idx_next = amo_uop_idx;
        if (dispatch_ready && opc_amo) amo_uop_idx_next = amo_uop_idx + 1'b1;
        if ((dispatch_ready && amo_complete) || kill_valid) amo_uop_idx_next = 'b0;

        amo_tmp_reg_next = amo_alloc_tmp_reg ? allocated_reg : amo_tmp_reg;
        amo_dst_reg_next = amo_alloc_dst_reg ? allocated_reg : amo_dst_reg;
        if (dispatch_ready && amo_complete) begin
            amo_tmp_reg_next = 'b0;
            amo_dst_reg_next = 'b0;
        end
        amo_parent_next = amo_opc_valid && amo_uop_idx == 2'b0 ? dispatch_id : amo_parent;
    end

    always_comb begin
        amo_illegal_instr = 1'b0;
        amo_uop           = RXVTypes::UOP_LW;
        amo_alu_op        = RXVTypes::ALU_ADD;
        amo_uop_wb        = 1'b0;
        amo_exec_pipe_en  = 'b0;
        amo_alloc_reg     = 1'b0;
        amo_rs1_is_dst    = 1'b0;
        amo_alloc_tmp_reg = 1'b0;
        amo_alloc_dst_reg = 1'b0;
        amo_rs2_is_tmp    = 1'b0;
        amo_rename_valid  = 1'b0;
        amo_op_type       = AMO_TYPE_LR;

        unique casez (funct7[6:2])
            // LR/SC
            5'b00010, 5'b00011: begin
                amo_num_uops = 3'd1;
                amo_op_type  = funct7[6:2] == 5'b00010 ? AMO_TYPE_LR : AMO_TYPE_SC;
            end
            // Fetch and Op
            5'b00000, 5'b00001, 5'b00100, 5'b01100, 5'b01000, 5'b10000, 5'b10100,
            5'b11000, 5'b11100: begin
                amo_num_uops = 3'd4;
                amo_op_type  = AMO_TYPE_FETCH_OP;
            end
            default: begin
                amo_num_uops      = 3'd1;
                amo_illegal_instr = 1'b1;
                amo_op_type       = AMO_TYPE_FETCH_OP;
            end
        endcase

        unique casez (funct7[6:2])
            5'b00000: amo_alu_op = RXVTypes::ALU_ADD;
            5'b00001: amo_alu_op = RXVTypes::ALU_RS2;
            5'b00100: amo_alu_op = RXVTypes::ALU_XOR;
            5'b01100: amo_alu_op = RXVTypes::ALU_AND;
            5'b01000: amo_alu_op = RXVTypes::ALU_OR;
            5'b10000: amo_alu_op = RXVTypes::ALU_MIN;
            5'b10100: amo_alu_op = RXVTypes::ALU_MAX;
            5'b11000: amo_alu_op = RXVTypes::ALU_MINU;
            5'b11100: amo_alu_op = RXVTypes::ALU_MAXU;
            default:  amo_alu_op = RXVTypes::ALU_ADD;
        endcase

        amo_opc_valid = opc_amo & ~amo_illegal_instr;

        unique case (amo_op_type)
            AMO_TYPE_FETCH_OP: begin
                unique case (amo_uop_idx)
                    2'b00: begin
                        amo_uop                         = RXVTypes::UOP_LW_ATOMIC;
                        amo_exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;
                        amo_alloc_dst_reg               = amo_opc_valid;
                        amo_uop_wb                      = 1'b1;
                    end
                    2'b01: begin
                        amo_uop                         = RXVTypes::UOP_ALU;
                        amo_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                        amo_rs1_is_dst                  = 1'b1;
                        amo_alloc_tmp_reg               = 1'b1;
                        amo_uop_wb                      = 1'b1;
                    end
                    2'b10: begin
                        amo_uop                         = RXVTypes::UOP_SW;
                        amo_exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;
                        amo_rs2_is_tmp                  = 1'b1;
                    end
                    2'b11: begin
                        amo_uop                         = RXVTypes::UOP_ALU;
                        amo_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                        amo_rename_valid                = |rd;
                    end
                    default: begin
                        amo_uop = RXVTypes::UOP_ALU;
                    end
                endcase
            end
            AMO_TYPE_LR: begin
                amo_uop                         = RXVTypes::UOP_LR;
                amo_exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;
                amo_uop_wb                      = 1'b1;
            end
            AMO_TYPE_SC: begin
                amo_uop                         = RXVTypes::UOP_SC;
                amo_exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;
                amo_uop_wb                      = 1'b1;
            end
            default: ;
        endcase

        amo_alloc_reg = amo_alloc_tmp_reg | amo_alloc_dst_reg;
        amo_complete  = 3'(amo_uop_idx) == amo_num_uops - 1'b1;
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

        unique casez (decode_instr[31:7])
            25'b0000_zzzz_zzzz_0000_0000_0000_0: begin  // FENCE
                misc_mem_uop           = RXVTypes::UOP_ALU;
                misc_mem_illegal_instr = 1'b0;
            end
            25'b0000_0000_0000_0000_0001_0000_0: begin  // FENCE.I
                misc_mem_uop           = RXVTypes::UOP_FENCEI;
                misc_mem_illegal_instr = 1'b0;
            end
            default: misc_mem_illegal_instr = 1'b1;
        endcase
    end

    always_comb begin
        logic csr_write;

        system_illegal_instr  = 1'b0;
        csr_op_next           = RXVTypes::CSR_SWAP;
        system_uop            = RXVTypes::UOP_ALU;
        system_have_writeback = 1'b0;
        csr_write             = 1'b0;
        system_exec_pipe_en   = 'b0;

        unique case (funct3)
            3'b000: begin
                unique casez (decode_instr[31:7])
                    25'b0000_0000_0000_0000_0000_0000_0: begin  // ECALL
                        system_uop                         = RXVTypes::UOP_ECALL;
                        system_illegal_instr               = 1'b0;
                        system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                    end
                    25'b0000_0000_0001_0000_0000_0000_0: begin  // EBREAK
                        system_uop                         = RXVTypes::UOP_EBREAK;
                        system_illegal_instr               = 1'b0;
                        system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                    end
                    25'b0001_0000_0010_0000_0000_0000_0: begin  // SRET
                        system_uop                         = RXVTypes::UOP_SRET;
                        system_illegal_instr               = 1'b0;
                        system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;

                        if (mstatus_in.tsr && current_privilege != RXVCSR::PRIV_M)
                            system_illegal_instr = 1'b1;
                    end
                    25'b0011_0000_0010_0000_0000_0000_0: begin  // MRET
                        system_uop                         = RXVTypes::UOP_MRET;
                        system_illegal_instr               = 1'b0;
                        system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;

                        if (current_privilege != RXVCSR::PRIV_M) system_illegal_instr = 1'b1;
                    end
                    25'b0001_0000_0101_0000_0000_0000_0: begin  // WFI
                        system_illegal_instr               = 1'b0;
                        system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                    end
                    25'b0001_001z_zzzz_zzzz_z000_0000_0: begin  // SFENCE.VMA
                        system_uop                         = RXVTypes::UOP_SFENCE_VMA;
                        system_illegal_instr               = 1'b0;
                        system_exec_pipe_en[EXEC_PIPE_LSU] = 1'b1;

                        if (current_privilege == RXVCSR::PRIV_U || mstatus_in.tvm)
                            system_illegal_instr = 1'b1;
                    end
                    default: system_illegal_instr = 1'b1;
                endcase
            end
            3'b001: begin  // CSRRW
                system_uop                         = RXVTypes::UOP_CSR;
                system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                csr_op_next                        = RXVTypes::CSR_SWAP;
                csr_write                          = 1'b1;
                system_have_writeback              = 1'b1;
                system_illegal_instr               = ~valid_csr_in;
            end
            3'b010: begin  // CSRRS
                system_uop                         = RXVTypes::UOP_CSR;
                system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                csr_op_next                        = ~|rs1 ? RXVTypes::CSR_READ : RXVTypes::CSR_SET;
                csr_write                          = |rs1;
                system_have_writeback              = 1'b1;
                system_illegal_instr               = ~valid_csr_in;
            end
            3'b011: begin  // CSRRC
                system_uop = RXVTypes::UOP_CSR;
                system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                csr_op_next = ~|rs1 ? RXVTypes::CSR_READ : RXVTypes::CSR_CLEAR;
                csr_write = |rs1;
                system_have_writeback = 1'b1;
                system_illegal_instr = ~valid_csr_in;
            end
            3'b101: begin  // CSRRWI
                system_uop                         = RXVTypes::UOP_CSRI;
                system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                csr_op_next                        = RXVTypes::CSR_SWAP;
                csr_write                          = |rs1;
                system_have_writeback              = 1'b1;
                system_illegal_instr               = ~valid_csr_in;
            end
            3'b110: begin  // CSRRSI
                system_uop = RXVTypes::UOP_CSRI;
                system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                csr_op_next = ~|decode_instr[19:15] ? RXVTypes::CSR_READ : RXVTypes::CSR_SET;
                csr_write = |rs1;
                system_have_writeback = 1'b1;
                system_illegal_instr = ~valid_csr_in;
            end
            3'b111: begin  // CSRRCI
                system_uop = RXVTypes::UOP_CSRI;
                system_exec_pipe_en[EXEC_PIPE_INT] = 1'b1;
                csr_op_next = ~|decode_instr[19:15] ? RXVTypes::CSR_READ : RXVTypes::CSR_CLEAR;
                csr_write = |decode_instr[19:15];
                system_have_writeback = 1'b1;
                system_illegal_instr = ~valid_csr_in;
            end
            default: system_illegal_instr = 1'b1;
        endcase

        if (csr_write && decode_csr_addr[11:10] == 2'b11) system_illegal_instr = 1'b1;
    end

    always_comb begin
        exec_alu_op_next = 'b0;
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_op}} & op_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_imm}} & imm_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_branch}} & branch_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_jalr}} & jalr_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_amo}} & amo_alu_op);
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
        exec_have_writeback_next |= opc_load;
        exec_have_writeback_next |= opc_mul & ~mul_illegal_instr;
        exec_have_writeback_next |= opc_div & ~div_illegal_instr;
        exec_have_writeback_next |= opc_amo & amo_uop_wb & ~amo_illegal_instr;

        if ((!amo_alloc_reg && ~|rd) || illegal_instruction) exec_have_writeback_next = 1'b0;
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
        exec_uop_next |= ({$bits(rxv_uop) {opc_store}} & store_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_load}} & load_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_mul}} & mul_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_div}} & div_uop);
        exec_uop_next |= ({$bits(rxv_uop) {opc_amo}} & amo_uop);
    end

    always_comb begin
        illegal_instruction = (opc_op & op_illegal_instr) |
            (opc_imm & imm_illegal_instr) |
            (opc_branch & branch_illegal_instr) |
            (opc_system & system_illegal_instr) |
            (opc_misc_mem & misc_mem_illegal_instr) |
            (opc_store & store_illegal_instr) |
            (opc_load & load_illegal_instr) |
            (opc_mul & mul_illegal_instr) |
            (opc_div & div_illegal_instr) |
            (opc_amo & amo_illegal_instr) |
            illegal_opcode;
    end

    always_comb begin
        system_stall   = opcode[6:2] == RXVTypes::OPC_SYSTEM && ~commit_buffer_empty;
        misc_mem_stall = opcode[6:2] == RXVTypes::OPC_MISC_MEM && ~commit_buffer_empty;
    end

    always_comb begin
        logic lsu_stall;
        logic int_stall;
        logic mul_stall;
        logic div_stall;

        lsu_stall = exec_pipe_en[EXEC_PIPE_LSU] && (!lsu_ready || lsu_busy);
        int_stall = exec_pipe_en[EXEC_PIPE_INT] && !int_ready;
        mul_stall = exec_pipe_en[EXEC_PIPE_MUL] && !mul_ready;
        // Divider isn't pipelined so busy may not yet be raised, check if
        // another divide was just started
        div_stall = exec_pipe_en[EXEC_PIPE_DIV] && (!div_ready || div_exec_busy || div_exec_valid);
        decode_be_stall      = decode_valid & (reg_alloc_empty | commit_buffer_full |
                                            ~src_regs_ready | system_stall | lsu_stall |
                                            int_stall | misc_mem_stall | mul_stall |
                                            div_stall);
        // Stall the front-end when either the back-end is stalled or we are in
        // a multi-uop instruction
        decode_fe_stall = decode_be_stall || (opc_amo && 3'(amo_uop_idx) < amo_num_uops - 1'b1);
    end

    always_comb begin
        dispatch_int = exec_pipe_en[EXEC_PIPE_INT] &&
            !illegal_instruction && decode_valid && !decode_be_stall &&
            !kill_valid && !exec_resteer;
        schedule_int = dispatch_int & exec_have_writeback_next;
    end

    always_comb begin
        dispatch_lsu = exec_pipe_en[EXEC_PIPE_LSU] &&
            !illegal_instruction && decode_valid && !decode_be_stall &&
            !kill_valid && !exec_resteer;
        schedule_lsu = dispatch_lsu & exec_have_writeback_next;
    end

    always_comb begin
        dispatch_mul = exec_pipe_en[EXEC_PIPE_MUL] &&
            !illegal_instruction && decode_valid && !decode_be_stall &&
            !kill_valid && !exec_resteer;
        schedule_mul = dispatch_mul & exec_have_writeback_next;
    end

    always_comb begin
        dispatch_div = exec_pipe_en[EXEC_PIPE_DIV] &&
            !illegal_instruction && decode_valid && !decode_be_stall &&
            !kill_valid && !exec_resteer;
        schedule_div = dispatch_div & exec_have_writeback_next;
    end

    always_comb begin
        rename_lookup_arch[0] = rs1;
        rename_lookup_arch[1] = rs2;
    end

    always_comb begin
        int_bypass_valid = int_exec_valid && exec_have_writeback &&
            (exec_uop == RXVTypes::UOP_ALU || exec_uop == RXVTypes::UOP_AUIPC ||
             exec_uop == RXVTypes::UOP_LUI);
    end

    always_comb begin
        exec_bypass_rs1_next = int_bypass_valid && last_rd_arch == rs1;
        exec_bypass_rs2_next = int_bypass_valid && last_rd_arch == rs2;
    end

    always_comb begin
        rs1_busy = busy_status[ra_phys];
        if (reg_wr_en && reg_wr_addr == ra_phys) rs1_busy = 1'b0;
        if (exec_bypass_rs1_next) rs1_busy = 1'b0;
    end

    always_comb begin
        rs2_busy = busy_status[rb_phys];
        if (reg_wr_en && reg_wr_addr == rb_phys) rs2_busy = 1'b0;
        if (exec_bypass_rs2_next) rs2_busy = 1'b0;
    end

    always_comb begin
        src_regs_ready = ~((have_rs1 & rs1_busy) | (have_rs2 & rs2_busy));
    end

    always_comb begin
        dispatch_ready = dispatch_int | dispatch_lsu | dispatch_mul | dispatch_div;
    end

    always_comb begin
        amo_stale_reg = 'b0;

        if (amo_uop_idx == 2'b10) amo_stale_reg = amo_tmp_reg;
        else if (amo_uop_idx == 2'b11) amo_stale_reg = |rd ? stale_phys_reg : amo_dst_reg;
    end

    always_comb begin
        if (amo_opc_valid && amo_op_type == AMO_TYPE_FETCH_OP) begin
            commit_dispatch.stale_phys    = amo_stale_reg;
            commit_dispatch.dest_reg.arch = rd;
            commit_dispatch.dest_reg.phys = amo_alloc_dst_reg ? allocated_reg : amo_dst_reg;
        end else begin
            commit_dispatch.stale_phys = exec_have_writeback_next ? stale_phys_reg : phys_reg_tag'('b0);
            commit_dispatch.dest_reg = exec_have_writeback_next ? rename_out : renamed_reg'('b0);
        end

        commit_dispatch.pc             = decode_pc;
        commit_dispatch.have_writeback = exec_have_writeback_next;
        commit_dispatch.have_rename    = rename_out_valid;
`ifdef RXV_TRACE
        if (amo_opc_valid && amo_op_type == AMO_TYPE_FETCH_OP) commit_dispatch.last = amo_complete;
        else commit_dispatch.last = 1'b1;

        commit_dispatch.parent_id = amo_opc_valid && amo_op_type == AMO_TYPE_FETCH_OP ? amo_parent : dispatch_id;
`endif  // RXV_TRACE

        commit_dispatch_valid = ~kill_valid & ~commit_buffer_full & (dispatch_ready | (decode_valid & illegal_instruction));
    end

    always_comb begin
        rename_out.arch = rd;
        rename_out.phys = opc_amo && amo_op_type == AMO_TYPE_FETCH_OP ? amo_dst_reg : allocated_reg;

        if (opc_amo && amo_op_type == AMO_TYPE_FETCH_OP)
            rename_out_valid = dispatch_ready & amo_rename_valid;
        else rename_out_valid = dispatch_ready & |rd & exec_have_writeback_next;
    end

    always_comb begin
        busy_reg_out   = allocated_reg;
        busy_valid_out = dispatch_ready & (|rd | amo_alloc_reg) & exec_have_writeback_next;
    end

    always_comb begin
        reg_alloc_valid = dispatch_ready & (|rd | amo_alloc_reg) & exec_have_writeback_next;
    end

    always_comb begin
        ra_phys = amo_rs1_is_dst ? amo_dst_reg : rename_lookup_phys[0];
        rb_phys = amo_rs2_is_tmp ? amo_tmp_reg : rename_lookup_phys[1];
    end

    always_comb begin
        decode_csr_addr = decode_instr[31:20];
    end

    always_comb begin
        decode_exception_next.pc = decode_pc;
        decode_exception_next.val = decode_instr;
        decode_exception_next.cause = RXVCSR::CAUSE_ILLEGAL_INSTR;
        decode_exception_next.valid = ~kill_valid & ~exec_resteer & ~commit_buffer_full & decode_valid & illegal_instruction;
        decode_exception_next.irq = 1'b0;
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

    RXVDFF int_exec_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dispatch_int),
        .q    (int_exec_valid)
    );

    RXVDFF lsu_exec_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dispatch_lsu),
        .q    (lsu_exec_valid)
    );

    RXVDFF mul_exec_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dispatch_mul),
        .q    (mul_exec_valid)
    );

    RXVDFF div_exec_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dispatch_div),
        .q    (div_exec_valid)
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

    RXVDFF #(
        .width($bits(amo_uop_idx))
    ) amo_uop_idx_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (amo_uop_idx_next),
        .q    (amo_uop_idx)
    );

    RXVDFF #(
        .width($bits(amo_tmp_reg))
    ) amo_tmp_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (amo_tmp_reg_next),
        .q    (amo_tmp_reg)
    );

    RXVDFF #(
        .width($bits(amo_dst_reg))
    ) amo_dst_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (amo_dst_reg_next),
        .q    (amo_dst_reg)
    );

    RXVDFF #(
        .width($bits(amo_parent))
    ) amo_parent_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (amo_parent_next),
        .q    (amo_parent)
    );

    always_ff @(posedge clk) begin
        if (decode_valid && !decode_be_stall && !kill_valid && !exec_resteer && amo_uop_idx == 'b0) begin
            trace_start_instruction(32'(dispatch_id), decode_pc, decode_pc, decode_instr,
                                    current_privilege);
        end else if (decode_valid && !decode_be_stall && !kill_valid && !exec_resteer && amo_uop_idx != 'b0) begin
            trace_uop(32'(amo_parent), 32'(dispatch_id));
        end

        if (decode_valid && decode_exception_next.valid) begin
            trace_start_instruction(32'(dispatch_id), decode_pc, decode_pc, decode_instr,
                                    current_privilege);
        end
    end

endmodule
