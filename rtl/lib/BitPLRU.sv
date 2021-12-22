`default_nettype none
module BitPLRU #(
    parameter width = 4,
    parameter depth = 32
) (
    input  logic                 clk,
    input  logic [addr_bits-1:0] read_index,
    input  logic [ way_bits-1:0] access_way,
    input  logic                 valid,
    output logic [ way_bits-1:0] lru_out
);

    localparam addr_bits = $clog2(depth);
    localparam way_bits = $clog2(width);

    wire  [    width-1:0] read_plru_ram_out;
    wire  [    width-1:0] read_plru;
    wire  [addr_bits-1:0] write_index;
    logic [    width-1:0] new_plru;
    wire  [    width-1:0] new_plru_reg;
    wire                  update;
    logic [    width-1:0] read_din;

    DPRAM #(
        .depth(depth),
        .width(width)
    ) DPRAM (
        .clk   (clk),
        .addr_a(read_index),
        .wren_a(1'b0),
        .din_a (read_din),
        .dout_a(read_plru_ram_out),
        .addr_b(write_index),
        .wren_b(update),
        .din_b (new_plru_reg),
        // verilator lint_off PINCONNECTEMPTY
        .dout_b()
        // verilator lint_on PINCONNECTEMPTY
    );

    RXVDFF #(
        .width(addr_bits)
    ) write_index_ff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (read_index),
        .q    (write_index)
    );

    RXVDFF #(
        .width(width)
    ) new_plru_dff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (new_plru),
        .q    (new_plru_reg)
    );

    RXVDFF update_dff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (valid),
        .q    (update)
    );

    assign read_plru = read_index == write_index && update ? new_plru_reg : read_plru_ram_out;

    always_comb begin
        read_din = width'('b0);
    end

    always_comb begin
        new_plru = read_plru;
        if (valid) begin
            new_plru[access_way] = 1'b1;
            if (&new_plru) begin
                new_plru             = 'b0;
                new_plru[access_way] = 1'b1;
            end
        end
    end

    always_comb begin
        integer i;
        lru_out = 'b0;
        for (i = 0; i < width; i = i + 1) begin : lru_lookup
            if (!read_plru[i]) begin
                lru_out = way_bits'(i);
            end
        end
    end

endmodule
