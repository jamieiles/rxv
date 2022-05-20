`include "RXV.svh"

import RXVTypes::rxv_alu_op;

module RXVALU (
    input  logic      [31:0] a,
    input  logic      [31:0] b,
    input  rxv_alu_op        op,
    output logic      [31:0] q,
    output logic             zero
);
    always_comb begin
        unique case (op)
            RXVTypes::ALU_ADD: q = a + b;
            RXVTypes::ALU_SUB: q = a - b;
            RXVTypes::ALU_SLL: q = a << b[4:0];
            RXVTypes::ALU_SLR: q = a >> b[4:0];
            RXVTypes::ALU_SRA: q = $signed(a) >>> b[4:0];
            RXVTypes::ALU_XOR: q = a ^ b;
            RXVTypes::ALU_OR: q = a | b;
            RXVTypes::ALU_AND: q = a & b;
            RXVTypes::ALU_SLT: q = {31'b0, $signed(a) < $signed(b)};
            RXVTypes::ALU_SLTU: q = {31'b0, a < b};
            RXVTypes::ALU_MIN: q = $signed(a) < $signed(b) ? a : b;
            RXVTypes::ALU_MAX: q = $signed(a) > $signed(b) ? a : b;
            RXVTypes::ALU_MINU: q = a < b ? a : b;
            RXVTypes::ALU_MAXU: q = a > b ? a : b;
            RXVTypes::ALU_RS2: q = b;
            default: q = 'b0;
        endcase

        zero = ~|q;
    end

endmodule
