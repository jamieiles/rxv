`include "RXV.svh"
module OneHotDecode #(
    parameter width = 1
) (
    input  logic [    width-1:0] d,
    output logic [out_width-1:0] q
);

    localparam out_width = $clog2(width);
    integer i;

    always_comb begin
        q = $clog2(width)'('b0);

        for (i = 0; i < width; i = i + 1) begin
            if (d[i]) begin
                assert (~|q);
                q |= out_width'(i);
            end
        end
    end

endmodule
