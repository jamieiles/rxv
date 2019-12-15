`default_nettype none
module DPRAM #(
    parameter depth = 32,
    parameter width = 8
)(
    input logic clk,
    // Port A
    input logic [addr_bits-1:0] addr_a,
    input logic wren_a,
    input logic [width-1:0] din_a,
    output logic [width-1:0] dout_a,
    // Port B
    input logic [addr_bits-1:0] addr_b,
    input logic wren_b,
    input logic [width-1:0] din_b,
    output logic [width-1:0] dout_b
);

localparam addr_bits = $clog2(depth);

logic [width-1:0] mem[0:depth-1];

always_ff @(posedge clk) begin
    if (wren_b)
        mem[addr_b] <= din_b;
    dout_b <= mem[addr_b];

    if (wren_a)
        mem[addr_a] <= din_a;
    dout_a <= mem[addr_a];
end

`ifdef FORMAL

`ifdef FORMAL_DPRAM
`define ASSUME assume
`else
`define ASSUME assert
`endif

(* anyconst *)  wire [addr_bits-1:0] f_addr;
reg [width-1:0] f_data;
reg f_past_valid = 1'b0;
integer i;

initial for (i = 0; i < depth; i = i + 1) begin
    mem[i] = 'b0;
end

always @(*)
    assert(mem[f_addr] == f_data);

initial assume(f_data == mem[f_addr]);

always @(*)
    `ASSUME(!(wren_a && wren_b && addr_a == addr_b));

always_ff @(posedge clk)
    f_past_valid <= 1'b1;

always_ff @(posedge clk) begin
    if (f_past_valid && $past(addr_a) == f_addr)
        assert(dout_a == $past(f_data));
    if (f_past_valid && $past(addr_b) == f_addr)
        assert(dout_b == $past(f_data));

    if (wren_b && addr_b == f_addr)
        f_data <= din_b;

    if (wren_a && addr_a == f_addr)
        f_data <= din_a;
end

`endif // FORMAL

endmodule