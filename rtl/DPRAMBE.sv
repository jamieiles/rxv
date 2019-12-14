`default_nettype none
module DPRAMBE #(
    parameter depth = 32,
    parameter byte_width = 4
)(
    input logic clk,
    // Port A
    input logic [addr_bits-1:0] addr_a,
    input logic wren_a,
    input logic [data_bits-1:0] din_a,
    input logic [byte_width-1:0] byte_en_a,
    output logic [data_bits-1:0] dout_a,
    // Port B
    input logic [addr_bits-1:0] addr_b,
    input logic wren_b,
    input logic [data_bits-1:0] din_b,
    output logic [data_bits-1:0] dout_b
);

localparam addr_bits = $clog2(depth);
localparam data_bits = 8 * byte_width;

logic [data_bits-1:0] mem[0:depth-1];

integer b;
always_ff @(posedge clk) begin
    if (wren_b)
        mem[addr_b] <= din_b;
    dout_b <= mem[addr_b];
end

always_ff @(posedge clk) begin
    if (wren_a) begin
        for (b = 0; b < byte_width; b++) begin
            if (byte_en_a[b])
                mem[addr_a][b*8:+8] <= din_a[b*8:+8];
        end
    end
    dout_a <= mem[addr_a];
end

`ifdef FORMAL

`ifdef FORMAL_DPRAMBE
`define ASSUME assume
`else
`define ASSUME assert
`endif

(* anyconst *)  wire [addr_bits-1:0] f_addr;
reg [data_bits-1:0] f_data;
reg f_past_valid = 1'b0;

always @(*)
    assert(mem[f_addr] == f_data);

initial `ASSUME(f_data == mem[f_addr]);

always_ff @(posedge clk)
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

    if (wren_a && addr_a == f_addr) begin
        for (b = 0; b < byte_width; b++) begin
            if (byte_en_a[b])
                f_data[b*8:+8] <= din_a[b*8:+8];
        end
    end
end

`endif // FORMAL

endmodule