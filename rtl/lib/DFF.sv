`default_nettype none
module DFF #(
    parameter width = 1,
    parameter reset_val = 0
) (
    input  logic             clk,
    input  logic             reset,
    input  logic             en,
    input  logic [width-1:0] d,
    output logic [width-1:0] q
);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            q <= reset_val;
        end else begin
            if (en) q <= d;
        end
    end

endmodule
