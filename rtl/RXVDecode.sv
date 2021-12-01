`default_nettype none

import RXVTypes::num_phys_regs;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::rxv_alu_op;
import RXVTypes::rxv_opcode_map;
import RXVTrace::trace_start_instruction;
import RXVTrace::trace_end_instruction;

module RXVDecode #(
    parameter int commit_order = 3
) (
    input  logic                            clk,
    input  logic                            reset,
    // From fetch
    input  logic                            decode_valid,
    input  logic        [             31:2] decode_pc,
    input  logic        [             31:2] decode_next_pc,
    input  logic        [             31:0] decode_instr,
    input  logic                            decode_predicted,
    input  logic                            decode_predict_taken,
    input  logic        [              1:0] decode_predict_strength,
    output logic                            decode_stall,
    output logic        [             31:2] decode_resume_tgt,
    // To register allocator
    input  logic                            reg_alloc_empty,
    output logic                            reg_alloc_valid,
    input  phys_reg_tag                     allocated_reg,
    // To commit buffer
    input  logic                            commit_buffer_full,
    output commit_entry                     commit_dispatch,
    output logic                            commit_dispatch_valid,
    input               [ commit_width-1:0] dispatch_id,
    // To scoreboard
    output phys_reg_tag                     busy_reg_out,
    output logic                            busy_valid_out,
    input  logic        [num_phys_regs-1:0] busy_status,
    // To renamer
    output renamed_reg                      rename_out,
    output logic                            rename_out_valid,
    input  phys_reg_tag                     stale_phys_reg,
    output arch_reg_tag                     rename_lookup_arch     [1:0],
    input  phys_reg_tag                     rename_lookup_phys     [1:0],
    // To register fetch
    output phys_reg_tag                     ra_phys,
    output phys_reg_tag                     rb_phys,
    // To exec
    output rxv_alu_op                       exec_alu_op,
    output logic                            exec_valid,
    output logic                            exec_have_writeback,
    output phys_reg_tag                     exec_rd,
    output              [ commit_width-1:0] exec_id,
    output logic        [             31:0] exec_immed,
    output logic                            exec_op2_immed
);

    wire [ 6:0] funct7 = decode_instr[31:25];
    wire [ 4:0] rs2 = decode_instr[24:20];
    wire [ 4:0] rs1 = decode_instr[19:15];
    wire [ 2:0] funct3 = decode_instr[14:12];
    wire [11:7] rd = decode_instr[11:7];
    wire [ 6:0] opcode = decode_instr[6:0];

    wire [31:0] i_immed = 32'($signed(decode_instr[31:20]));

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic             src_regs_ready;
    logic             illegal_instruction;
    logic             illegal_opcode;

    logic      [ 3:0] exec_alu_op_next;
    logic             exec_valid_next;
    logic             exec_have_writeback_next;
    logic      [31:0] exec_immed_next;
    logic             exec_op2_immed_next;

    logic             opc_op;
    rxv_alu_op        op_alu_op;
    logic             op_illegal_instr;

    logic             opc_imm;
    rxv_alu_op        imm_alu_op;
    logic             imm_illegal_instr;

    always_comb begin
        opc_op              = 1'b0;
        opc_imm = 1'b0;
        exec_op2_immed_next = 1'b0;
        exec_immed_next     = 'b0;

        unique case (decode_instr[6:2])
            RXVTypes::OPC_OP: begin
                illegal_opcode = 1'b0;
                opc_op         = 1'b1;
            end
            RXVTypes::OPC_IMM: begin
                illegal_opcode      = 1'b0;
                opc_imm             = 1'b1;
                exec_immed_next     = i_immed;
                exec_op2_immed_next = 1'b1;
            end
            default: illegal_opcode = 1'b1;
        endcase

        if (decode_instr[1:0] != 2'b11) illegal_opcode = 1'b1;
    end

    always_comb begin
        op_illegal_instr = 1'b0;
        op_alu_op        = RXVTypes::ALU_ADD;

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
        exec_alu_op_next = 'b0;
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_op & ~op_illegal_instr}} & op_alu_op);
        exec_alu_op_next |= ({$bits(rxv_alu_op) {opc_imm & ~imm_illegal_instr}} & imm_alu_op);
    end

    always_comb begin
        exec_have_writeback_next = 1'b0;
        exec_have_writeback_next |= opc_op & ~op_illegal_instr;
        exec_have_writeback_next |= opc_imm & ~imm_illegal_instr;
    end

    always_comb begin
        illegal_instruction = (opc_op & op_illegal_instr) | (opc_imm & imm_illegal_instr) | illegal_opcode;
    end

    always_comb begin
        decode_stall      = reg_alloc_empty | commit_buffer_full | ~src_regs_ready;
        decode_resume_tgt = decode_pc;
    end

    always_comb begin
        exec_valid_next = ~illegal_instruction & decode_valid & ~decode_stall;
    end

    always_comb begin
        rename_lookup_arch[0] = decode_instr[19:15];
        rename_lookup_arch[1] = decode_instr[24:20];
    end

    always_comb begin
        src_regs_ready = ~busy_status[rename_lookup_phys[0]] & ~busy_status[rename_lookup_phys[1]];
    end

    always_comb begin
        commit_dispatch.stale_phys     = stale_phys_reg;
        commit_dispatch.dest_reg       = rename_out;
        commit_dispatch.pc             = decode_pc;
        commit_dispatch.have_writeback = exec_have_writeback_next;

        commit_dispatch_valid          = exec_valid_next;
    end

    always_comb begin
        rename_out.arch  = decode_instr[11:7];
        rename_out.phys  = |rename_out.arch ? allocated_reg : 'b0;

        rename_out_valid = exec_valid_next & |rename_out.arch;
    end

    always_comb begin
        busy_reg_out   = rename_out.phys;
        busy_valid_out = exec_valid_next;
    end

    always_comb begin
        reg_alloc_valid = exec_valid_next;
    end

    always_comb begin
        ra_phys = rename_lookup_phys[0];
        rb_phys = rename_lookup_phys[1];
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

    RXVDFF exec_op2_immed_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_op2_immed_next),
        .q    (exec_op2_immed)
    );

    always_ff @(posedge clk) begin
        if (decode_valid && !decode_stall) begin
            trace_start_instruction(32'(dispatch_id), decode_pc, decode_instr, 2'b11);
        end
    end

endmodule
