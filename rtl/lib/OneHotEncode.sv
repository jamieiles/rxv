// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"
module OneHotEncode #(
    parameter width = 1
) (
    input  logic [in_width-1:0] d,
    output logic [   width-1:0] q
);

    localparam in_width = $clog2(width);

    always_comb begin
        q    = width'('b0);
        q[d] = 1'b1;
    end

endmodule
