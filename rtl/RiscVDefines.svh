localparam INSTR_ECALL  = 32'h00000073,
           INSTR_EBREAK = 32'h00100073,
           INSTR_MRET   = 32'h30200073,
	       INSTR_WFI	= 32'h10500073;

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

localparam RXV_MARCHID = 32'h72787600;