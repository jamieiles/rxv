`include "RXV.svh"
module RAMBE #(
    parameter depth = 32,
    parameter byte_width = 4
) (
    input  logic                  clk,
    input  logic [ addr_bits-1:0] addr,
    input  logic                  wren,
    input  logic [ data_bits-1:0] din,
    input  logic [byte_width-1:0] byte_en,
    output logic [ data_bits-1:0] dout
);

    localparam addr_bits = $clog2(depth);
    localparam data_bits = 8 * byte_width;

    logic   [byte_width-1:0][7:0] mem[0:depth-1];

    integer                       a;

    always_ff @(posedge clk) begin
        if (wren) begin
            for (a = 0; a < byte_width; a++) begin
                if (byte_en[a]) mem[addr][a] <= din[a*8+:8];
            end
        end
        dout <= mem[addr];
    end

    integer i;
    initial begin
        for (i = 0; i < depth; i = i + 1) mem[i] = data_bits'(1'b0);
    end

    `include "RAMBE_formal.sv"

endmodule
