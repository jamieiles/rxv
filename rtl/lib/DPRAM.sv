`default_nettype none
module DPRAM #(
    parameter depth = 32,
    parameter width = 8
) (
    input  logic                 clk,
    // Port A
    input  logic [addr_bits-1:0] addr_a,
    input  logic                 wren_a,
    input  logic [    width-1:0] din_a,
    output logic [    width-1:0] dout_a,
    // Port B
    input  logic [addr_bits-1:0] addr_b,
    input  logic                 wren_b,
    input  logic [    width-1:0] din_b,
    output logic [    width-1:0] dout_b
);

    localparam addr_bits = $clog2(depth);

    logic [width-1:0] mem[0:depth-1];

    always_ff @(posedge clk) begin
        if (wren_b) begin
            mem[addr_b] <= din_b;
        end
        dout_b <= mem[addr_b];

        if (wren_a) begin
            mem[addr_a] <= din_a;
        end
        dout_a <= mem[addr_a];
    end

    `include "DPRAM_formal.sv"

endmodule
