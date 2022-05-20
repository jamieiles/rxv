`include "RXV.svh"

import RXVTypes::num_phys_regs;
import RXVTypes::phys_reg_tag;

module RXVRegisterAllocator #(
    parameter num_regs = num_phys_regs
) (
    input  logic        clk,
    input  logic        reset,
    // Consumer
    output logic        empty,
    input  logic        pop,
    output phys_reg_tag pop_reg,
    // Producer
    input  logic        push,
    input  phys_reg_tag push_reg
);

    localparam addr_bits = $clog2(num_regs);

    logic [ num_regs-1:0] free_map;
    logic [ num_regs-1:0] free_map_next;
    logic                 empty_next;
    logic [addr_bits-1:0] pop_reg_next;

    always_comb begin
        free_map_next = free_map;
        if (push) free_map_next[push_reg] = 1'b1;
        if (pop) free_map_next[pop_reg] = 1'b0;
        empty_next = ~|free_map_next;
    end

    always_comb begin
        integer i;

        pop_reg_next = 'b0;
        for (i = num_regs - 1; i >= 0; i = i - 1)
            if (free_map_next[i]) pop_reg_next = addr_bits'(i);
    end

    RXVDFF empty_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (empty_next),
        .q    (empty)
    );

    RXVDFF #(
        .width(addr_bits)
    ) pop_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (pop_reg_next),
        .q    (pop_reg)
    );

    RXVDFF #(
        .width    (num_regs),
        // Register 0 is never allocated as it is the zero register
        .reset_val({{num_regs - 1{1'b1}}, 1'b0})
    ) free_map_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (free_map_next),
        .q    (free_map)
    );

    RXVAssert double_free (
        .clk      (clk),
        .en       (push),
        .condition(!free_map[push_reg])
    );

    RXVAssert push_zero (
        .clk      (clk),
        .en       (push),
        .condition(|push_reg)
    );

    RXVAssert double_alloc (
        .clk      (clk),
        .en       (pop),
        .condition(free_map[pop_reg])
    );

    RXVAssert pop_zero (
        .clk      (clk),
        .en       (pop),
        .condition(|pop_reg)
    );

endmodule
