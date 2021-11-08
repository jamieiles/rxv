`ifdef FORMAL

`ifdef FORMAL_DPRAM
`define ASSUME assume
`else
`define ASSUME assert
`endif

(* anyconst *)wire    [addr_bits-1:0] f_addr;
reg     [    width-1:0] f_data;
reg                     f_past_valid = 1'b0;
integer                 i;

initial begin
    for (i = 0; i < depth; i = i + 1) begin
        mem[i] = 'b0;
    end
end

always @(*) begin
    assert (mem[f_addr] == f_data);
end

initial begin
    assume (f_data == mem[f_addr]);
end

always_comb begin
    `ASSUME(!(wren_a && wren_b && addr_a == addr_b));
end

always_ff @(posedge clk) begin
    f_past_valid <= 1'b1;
end

always_ff @(posedge clk) begin
    if (f_past_valid && $past(addr_a) == f_addr) begin
        assert (dout_a == $past(f_data));
    end
    if (f_past_valid && $past(addr_b) == f_addr) begin
        assert (dout_b == $past(f_data));
    end

    if (wren_b && addr_b == f_addr) begin
        f_data <= din_b;
    end

    if (wren_a && addr_a == f_addr) begin
        f_data <= din_a;
    end
end

`endif  // FORMAL
