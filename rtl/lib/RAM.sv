`include "RXV.svh"
module RAM #(
    parameter depth = 32,
    parameter width = 8
) (
    input  logic                 clk,
    input  logic [addr_bits-1:0] addr,
    input  logic                 wren,
    input  logic [    width-1:0] din,
    output logic [    width-1:0] dout
);

    localparam addr_bits = $clog2(depth);

    logic [width-1:0] mem[0:depth-1];

    always_ff @(posedge clk) begin
        if (wren) begin
            mem[addr] <= din;
        end
        dout <= wren ? din : mem[addr];
    end

    integer i;
    initial begin
        for (i = 0; i < depth; i = i + 1) mem[i] = width'(1'b0);
    end

    `include "RAM_formal.sv"

endmodule
