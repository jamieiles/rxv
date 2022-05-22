module RAMBE #(
    parameter depth      = 32,
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

    wire [byte_width-1:0] wea = byte_en & {byte_width{wren}};

    xpm_memory_spram #(
        .ADDR_WIDTH_A      (addr_bits),
        .BYTE_WRITE_WIDTH_A(8),
        .MEMORY_PRIMITIVE  ("block"),
        .MEMORY_SIZE       (data_bits * depth),
        .READ_DATA_WIDTH_A (data_bits),
        .READ_LATENCY_A    (1),
        .WRITE_DATA_WIDTH_A(data_bits),
        .WRITE_MODE_A      ("write_first")
    ) ram (
        .addra(addr),
        .clka (clk),
        .dina (din),
        .douta(dout),
        .ena  (1'b1),
        .rsta (1'b0),
        .wea  (wea)
    );

endmodule
