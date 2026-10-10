// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"
module BitPLRU #(
    parameter width = 4,
    parameter depth = 32
) (
    `POWER_PIN_PORTS
    input  logic                 clk,
    input  logic                 reset,
    input  logic [addr_bits-1:0] read_index,
    input  logic [ way_bits-1:0] access_way,
    input  logic                 valid,
    output logic [ way_bits-1:0] lru_out
);

    localparam addr_bits = $clog2(depth);
    localparam way_bits = $clog2(width);

    // read_index is the set being looked up, valid+access_way give the way
    // that was accessed in that set on the following cycle (the tag compare)
    // and lru_out is the PLRU way for that set in the same cycle.  Updates
    // are registered and written back the cycle after, so the last two
    // updates are forwarded as they are not yet visible in the RAM output.
    wire  [    width-1:0] read_plru_ram_out;
    wire  [    width-1:0] read_plru;
    wire  [addr_bits-1:0] lookup_index;
    wire  [addr_bits-1:0] write_index;
    wire  [addr_bits-1:0] write_index_q;
    logic [    width-1:0] new_plru;
    wire  [    width-1:0] new_plru_reg;
    wire  [    width-1:0] new_plru_reg_q;
    wire                  update;
    wire                  update_q;

    DPRAM #(
        .depth(depth),
        .width(width)
    ) DPRAM (
        `POWER_PIN_CONNECT
        .clk   (clk),
        .reset (reset),
        .addr_a(read_index),
        .dout_a(read_plru_ram_out),
        .addr_b(write_index),
        .wren_b(update),
        .din_b (new_plru_reg)
    );

    RXVDFF #(
        .width(addr_bits)
    ) lookup_index_ff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (read_index),
        .q    (lookup_index)
    );

    RXVDFF #(
        .width(addr_bits)
    ) write_index_ff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (lookup_index),
        .q    (write_index)
    );

    RXVDFF #(
        .width(addr_bits)
    ) write_index_q_ff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (write_index),
        .q    (write_index_q)
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

    RXVDFF #(
        .width(width)
    ) new_plru_q_dff (
        .clk  (clk),
        .reset(1'b0),
        .en   (1'b1),
        .d    (new_plru_reg),
        .q    (new_plru_reg_q)
    );

    RXVDFF update_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (valid),
        .q    (update)
    );

    RXVDFF update_q_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (update),
        .q    (update_q)
    );

    assign read_plru = update && write_index == lookup_index ? new_plru_reg :
        update_q && write_index_q == lookup_index ? new_plru_reg_q : read_plru_ram_out;

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
