`ifdef FORMAL

`ifdef FORMAL_RAMBE
`define ASSUME assume
`else
`define ASSUME assert
`endif

(* anyconst *)wire    [addr_bits-1:0] f_addr;
reg     [data_bits-1:0] f_data;
reg                     f_past_valid = 1'b0;
integer                 i;

initial
    for (i = 0; i < depth; i = i + 1) begin
        mem[i] = 'b0;
    end

always_comb assert (mem[f_addr] == f_data);

initial assume (f_data == mem[f_addr]);

always_ff @(posedge clk) f_past_valid <= 1'b1;

always_ff @(posedge clk) begin
    if (f_past_valid && $past(addr) == f_addr) assert (dout == $past(f_data));

    if (wren && addr == f_addr) begin
        for (a = 0; a < byte_width; a++) begin
            if (byte_en[a]) f_data[a*8+:8] <= din[a*8+:8];
        end
    end
end

`endif  // FORMAL
