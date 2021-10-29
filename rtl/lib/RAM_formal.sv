`ifdef FORMAL

`ifdef FORMAL_RAM
`define ASSUME assume
`else
`define ASSUME assert
`endif

(* anyconst *) wire [addr_bits-1:0] f_addr;
reg [width-1:0] f_data;
reg f_past_valid = 1'b0;
integer i;

initial for (i = 0; i < depth; i = i + 1) begin
    mem[i] = 'b0;
end

always @(*)
    assert(mem[f_addr] == f_data);

initial assume(f_data == mem[f_addr]);

always_ff @(posedge clk)
    f_past_valid <= 1'b1;

always_ff @(posedge clk) begin
    if (f_past_valid && $past(addr) == f_addr)
        assert(dout == $past(f_data));

    if (wren && addr == f_addr)
        f_data <= din;
end

`endif // FORMAL
