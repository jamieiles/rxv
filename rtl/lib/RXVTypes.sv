// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
package RXVTypes;

    localparam num_arch_regs  /* verilator public */ = 32;
    localparam num_phys_regs  /* verilator public */ = 48;
    localparam arch_reg_bits  /* verilator public */ = $clog2(num_arch_regs);
    localparam phys_reg_bits  /* verilator public */ = $clog2(num_phys_regs);
    // verilator lint_off UNUSED
    localparam int int_latency = 1;
    localparam int lsu_latency = 3;
    localparam int mul_latency = 5;
    // MUL only needs the low word which is complete a stage earlier
    localparam int mul_lo_latency = 4;
    localparam int div_latency = 33;
    localparam int commit_order = 3;
    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);
    // verilator lint_on UNUSED

    typedef logic [arch_reg_bits-1:0] arch_reg_tag;
    typedef logic [phys_reg_bits-1:0] phys_reg_tag;

    typedef struct packed {
        arch_reg_tag arch;
        phys_reg_tag phys;
    } renamed_reg;

    typedef struct packed {
        phys_reg_tag stale_phys;
        renamed_reg dest_reg;
        logic have_writeback;
        logic have_rename;
`ifdef RXV_TRACE
        logic last;
        logic [commit_width-1:0] parent_id;
`endif  // RXV_TRACE
    } commit_entry;

    typedef struct packed {
        logic [31:2] prediction;
        logic [1:0]  predict_strength;
        logic        predict_taken;
        logic        predicted;
    } rxv_prediction;

    typedef enum logic [3:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_SLL,
        ALU_SLR,
        ALU_SRA,
        ALU_XOR,
        ALU_OR,
        ALU_AND,
        ALU_SLT,
        ALU_SLTU,
        ALU_MIN,
        ALU_MAX,
        ALU_MINU,
        ALU_MAXU,
        ALU_RS2
    } rxv_alu_op  /* verilator public */;

    typedef enum logic [4:0] {
        PMU_NONE,
        PMU_CYCLES,
        PMU_INSTRET,
        PMU_BRANCH,
        PMU_BRANCH_MISPRED,
        PMU_FE_STALL,
        PMU_BE_STALL,
        PMU_L1D_READ,
        PMU_L1D_READ_MISS,
        PMU_L1D_WRITE,
        PMU_L1D_WRITE_MISS,
        PMU_L1I_READ,
        PMU_L1I_READ_MISS,
        PMU_DTLB_READ,
        PMU_DTLB_READ_MISS,
        PMU_ITLB_READ,
        PMU_ITLB_READ_MISS
    } rxv_pmu_evt  /* verilator public */;

    localparam pmu_num_events  /* verilator public */ = PMU_ITLB_READ_MISS + 1;
    localparam rxv_pmu_evt_bits = $clog2(pmu_num_events);
    typedef logic [pmu_num_events-1:0] pmu_evt_bus;
    typedef logic [rxv_pmu_evt_bits-1:0] pmu_evt_sel;

    // Where exec takes an operand from: the register file or a result
    // forwarded from a pipe before it is written back.
    typedef enum logic [1:0] {
        OPERAND_RF  = 2'b00,
        OPERAND_INT = 2'b01,
        OPERAND_LSU = 2'b10,
        OPERAND_MUL = 2'b11
    } rxv_operand_src;

    typedef enum logic [1:0] {
        CSR_SWAP,
        CSR_SET,
        CSR_CLEAR,
        CSR_READ
    } rxv_csr_op  /* verilator public */;

    typedef enum logic [4:0] {
        OPC_LOAD     = 5'b00000,
        OPC_LOAD_FP  = 5'b00001,
        OPC_CUSTOM_0 = 5'b00010,
        OPC_MISC_MEM = 5'b00011,
        OPC_IMM      = 5'b00100,
        OPC_AUIPC    = 5'b00101,
        OPC_IMM32    = 5'b00111,

        OPC_STORE    = 5'b01000,
        OPC_STORE_FP = 5'b01001,
        OPC_CUSTOM_1 = 5'b01010,
        OPC_AMO      = 5'b01011,
        OPC_OP       = 5'b01100,
        OPC_LUI      = 5'b01101,
        OPC_OP32     = 5'b01110,

        OPC_MADD     = 5'b10000,
        OPC_MSUB     = 5'b10001,
        OPC_NMSUB    = 5'b10010,
        OPC_NMADD    = 5'b10011,
        OPC_FP       = 5'b10100,
        OPC_CUSTOM_2 = 5'b10110,

        OPC_BRANCH   = 5'b11000,
        OPC_JALR     = 5'b11001,
        OPC_JAL      = 5'b11011,
        OPC_SYSTEM   = 5'b11100,
        OPC_CUSTOM_3 = 5'b11110
    } rxv_opcode;

    typedef enum logic [5:0] {
        UOP_ALU,
        UOP_BEQ,
        UOP_BNE,
        UOP_BLT,
        UOP_BGE,
        UOP_JAL,
        UOP_JALR,
        UOP_LUI,
        UOP_AUIPC,
        UOP_CSR,
        UOP_CSRI,
        UOP_MRET,
        UOP_SRET,
        UOP_ECALL,
        UOP_EBREAK,
        UOP_LB,
        UOP_LH,
        UOP_LW,
        UOP_LW_ATOMIC,
        UOP_LR,
        UOP_SC,
        UOP_LBU,
        UOP_LHU,
        UOP_SB,
        UOP_SH,
        UOP_SW,
        UOP_FENCEI,
        UOP_MUL,
        UOP_MULH,
        UOP_MULHSU,
        UOP_MULHU,
        UOP_DIV,
        UOP_DIVU,
        UOP_REM,
        UOP_REMU,
        UOP_SFENCE_VMA_ALL,
        UOP_SFENCE_VMA_ASID,
        UOP_SFENCE_VMA_ADDR,
        UOP_SFENCE_VMA_ASID_ADDR,
        // CBO.CLEAN, CBO.FLUSH and CBO.INVAL are all performed as a flush
        UOP_CBO_FLUSH
    } rxv_uop  /* verilator public */;

    // verilator lint_off UNUSED
    function logic [31:0] i_immed;
        input logic [31:0] instr;

        i_immed = 32'($signed(instr[31:20]));
    endfunction

    function logic [31:0] j_immed;
        input logic [31:0] instr;

        j_immed = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:25], instr[24:21], 1'b0};
    endfunction

    function logic [31:0] b_immed;
        input logic [31:0] instr;

        b_immed = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    endfunction

    function logic [31:0] u_immed;
        input logic [31:0] instr;

        u_immed = {instr[31:12], 12'b0};
    endfunction

    function logic [31:0] s_immed;
        input logic [31:0] instr;

        s_immed = 32'($signed({instr[31:25], instr[11:7]}));
    endfunction
    // verilator lint_on UNUSED

`ifdef verilator
    function commit_entry make_commit_entry;
        // verilator public
        input phys_reg_tag stale_phys_reg;
        input arch_reg_tag renamed_arch;
        input phys_reg_tag renamed_phys;
        input logic have_writeback;

        begin
            make_commit_entry                = 'b0;
            make_commit_entry.stale_phys     = stale_phys_reg;
            make_commit_entry.dest_reg.arch  = renamed_arch;
            make_commit_entry.dest_reg.phys  = renamed_phys;
            make_commit_entry.have_writeback = have_writeback;
        end
    endfunction

    // verilator lint_off UNUSED

    function phys_reg_tag commit_entry_stale;
        // verilator public
        input commit_entry ce;

        commit_entry_stale = ce.stale_phys;
    endfunction

    function arch_reg_tag commit_entry_dest_arch;
        // verilator public
        input commit_entry ce;

        commit_entry_dest_arch = ce.dest_reg.arch;
    endfunction

    function phys_reg_tag commit_entry_dest_phys;
        // verilator public
        input commit_entry ce;

        commit_entry_dest_phys = ce.dest_reg.phys;
    endfunction

    function logic commit_entry_have_writeback;
        // verilator public
        input commit_entry ce;

        commit_entry_have_writeback = ce.have_writeback;
    endfunction

    // verilator lint_on UNUSED
`endif

endpackage
