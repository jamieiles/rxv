module RegFile(input logic clk,
               // verilator lint_off UNUSED
               input logic reset,
               // verilator lint_on UNUSED
               input logic [4:0] rd_addr_a,
               output logic [31:0] rd_data_a,
               input logic [4:0] rd_addr_b,
               output logic [31:0] rd_data_b,
               input logic wr_en,
               input logic [4:0] wr_addr,
               input logic [31:0] wr_data);

logic [31:0] bank_a[0:31];
logic [31:0] bank_b[0:31];

always_ff @(posedge clk) begin
    if (wr_en && |wr_addr) begin
        bank_a[wr_addr] <= wr_data;
        bank_b[wr_addr] <= wr_data;
    end

    rd_data_a <= wr_en && wr_addr == rd_addr_a && |wr_addr ? wr_data : bank_a[rd_addr_a];
    rd_data_b <= wr_en && wr_addr == rd_addr_b && |wr_addr ? wr_data : bank_b[rd_addr_b];
end

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
