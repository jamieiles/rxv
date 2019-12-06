module RegFile(
    input logic clk,
    // verilator lint_off UNUSED
    input logic reset,
    // verilator lint_on UNUSED
    input logic [4:0] rd_addr_a,
    output logic [31:0] rd_data_a,
    input logic [4:0] rd_addr_b,
    output logic [31:0] rd_data_b,
    input logic wr_en,
    input logic [4:0] wr_addr,
    input logic [31:0] wr_data
);

logic [31:0] bank_a[0:31];
logic [31:0] bank_b[0:31];
`ifdef ZERO_REGS
integer i;
`endif

reg [31:0] q_a, q_b, bypass_data;
reg bypass_a, bypass_b;

always_ff @(posedge clk
`ifdef ZERO_REGS
        or posedge reset
`endif
        ) begin

`ifdef ZERO_REGS
    if (reset) begin
        for (i = 0; i < 32; i = i + 1) begin
            bank_a[i] <= 32'b0;
            bank_b[i] <= 32'b0;
        end
    end else begin
`endif
        if (wr_en && |wr_addr) begin
            bank_a[wr_addr] <= wr_data;
            bank_b[wr_addr] <= wr_data;
        end

        q_a <= bank_a[rd_addr_a];
        q_b <= bank_b[rd_addr_b];
        bypass_data <= wr_data;

        bypass_a <= wr_en && wr_addr == rd_addr_a && |wr_addr;
        bypass_b <= wr_en && wr_addr == rd_addr_b && |wr_addr;
`ifdef ZERO_REGS
    end
`endif
end

assign rd_data_a = bypass_a ? bypass_data : q_a;
assign rd_data_b = bypass_b ? bypass_data : q_b;

`ifdef verilator
export "DPI-C" function write_reg;

function void write_reg;
    input int r;
    input int v;

    bank_a[r] = v;
    bank_b[r] = v;
endfunction
`endif // verilator


endmodule
