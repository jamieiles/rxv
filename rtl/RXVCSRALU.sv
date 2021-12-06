`default_nettype none

import RXVTypes::rxv_csr_op;

module RXVCSRALU (
    input  logic      [31:0] old_val,
    input  logic      [31:0] new_val,
    input  rxv_csr_op        op,
    output logic      [31:0] q
);
    always_comb begin
        unique case (op)
            RXVTypes::CSR_SWAP: q = new_val;
            RXVTypes::CSR_SET: q = old_val | new_val;
            RXVTypes::CSR_CLEAR: q = old_val & ~new_val;
            RXVTypes::CSR_READ: q = old_val;
            default: q = 'b0;
        endcase
    end

endmodule
