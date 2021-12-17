package RXVTypes;

    localparam num_arch_regs  /* verilator public */ = 32;
    localparam num_phys_regs  /* verilator public */ = 48;
    localparam arch_reg_bits  /* verilator public */ = $clog2(num_arch_regs);
    localparam phys_reg_bits  /* verilator public */ = $clog2(num_phys_regs);
    // verilator lint_off UNUSED
    localparam int_latency = 1;
    localparam lsu_latency = 3;
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
        logic [31:2] pc;
        logic have_writeback;
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
        ALU_SLTU
    } rxv_alu_op  /* verilator public */;

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

    typedef enum logic [4:0] {
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
        UOP_ECALL,
        UOP_EBREAK,
        UOP_LB,
        UOP_LH,
        UOP_LW,
        UOP_LBU,
        UOP_LHU,
        UOP_SB,
        UOP_SH,
        UOP_SW
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
        input logic [31:2] pc;
        input logic have_writeback;

        begin
            make_commit_entry                = 'b0;
            make_commit_entry.stale_phys     = stale_phys_reg;
            make_commit_entry.dest_reg.arch  = renamed_arch;
            make_commit_entry.dest_reg.phys  = renamed_phys;
            make_commit_entry.pc             = pc;
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

    function logic [31:2] commit_entry_pc;
        // verilator public
        input commit_entry ce;

        commit_entry_pc = ce.pc;
    endfunction

    function logic commit_entry_have_writeback;
        // verilator public
        input commit_entry ce;

        commit_entry_have_writeback = ce.have_writeback;
    endfunction

    // verilator lint_on UNUSED
`endif

endpackage
