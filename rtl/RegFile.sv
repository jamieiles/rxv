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

    rd_data_a <= bank_a[rd_addr_a];
    rd_data_b <= bank_b[rd_addr_b];
end

endmodule
