`default_nettype none

module Fifo #(
    parameter int data_width = 32,
    parameter int order      = 3
) (
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  flush,
    // Write port
    input  logic                  wr_en,
    input  logic [data_width-1:0] wr_data,
    output logic [  ptr_bits-1:0] wr_ptr,
    // Read port
    input  logic                  rd_en,
    output logic [data_width-1:0] rd_data,
    output logic [  ptr_bits-1:0] rd_ptr,
    output logic                  empty,
    output logic                  full
);

    localparam depth = (1 << order);
    localparam ptr_bits = $clog2(depth);

    logic [data_width-1:0] mem         [depth-1:0];
    logic [  ptr_bits-1:0] rd_ptr_next;
    logic [  ptr_bits-1:0] wr_ptr_next;
    logic                  empty_next;
    logic                  full_next;
    logic [     depth-1:0] entry_wr_en;

    OneHotEncode #(
        .width(depth)
    ) write_encode (
        .d(wr_ptr),
        .q(entry_wr_en)
    );

    genvar i;
    generate
        for (i = 0; i < depth; i = i + 1) begin : gen_fifo
            RXVDFF #(
                .width(data_width)
            ) mem_n_dff (
                .clk  (clk),
                .reset(reset),
                .en   (entry_wr_en[i]),
                .d    (wr_data),
                .q    (mem[i])
            );
        end
    endgenerate

    always_comb begin
        wr_ptr_next = wr_ptr;
        if (wr_en && !full) wr_ptr_next = wr_ptr + 1'b1;
        if (flush) wr_ptr_next = {ptr_bits{1'b0}};
    end

    always_comb begin
        rd_ptr_next = rd_ptr;
        if (rd_en && !empty) rd_ptr_next = rd_ptr + 1'b1;
        if (flush) rd_ptr_next = {ptr_bits{1'b0}};
    end

    always_comb begin
        rd_data    = mem[rd_ptr];
        empty_next = rd_ptr_next == wr_ptr_next;
        full_next  = wr_ptr_next + 1'b1 == rd_ptr_next;
    end

    RXVDFF #(
        .reset_val(1'b1)
    ) empty_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (empty_next),
        .q    (empty)
    );

    RXVDFF full_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (full_next),
        .q    (full)
    );

    RXVDFF #(
        .width(ptr_bits)
    ) rd_ptr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_ptr_next),
        .q    (rd_ptr)
    );

    RXVDFF #(
        .width(ptr_bits)
    ) wr_ptr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_ptr_next),
        .q    (wr_ptr)
    );

endmodule
