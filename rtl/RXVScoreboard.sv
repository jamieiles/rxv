`include "RXV.svh"

import RXVTypes::num_phys_regs;
import RXVTypes::phys_reg_tag;

module RXVScoreboard (
    input  logic                            clk,
    input  logic                            reset,
    // Allocation
    input  phys_reg_tag                     busy_reg_in,
    input  logic                            busy_valid_in,
    // Kill port
    input  phys_reg_tag                     kill_reg_in,
    input  logic                            kill_valid_in,
    // Writeback port
    input  phys_reg_tag                     writeback_reg_in,
    input  logic                            writeback_valid_in,
    // Busy status
    output logic        [num_phys_regs-1:0] busy_out
);

    logic [num_phys_regs-1:0] busy_next;

    always_comb begin
        busy_next = busy_out;

        if (busy_valid_in && |busy_reg_in) busy_next[busy_reg_in] = 1'b1;
        if (kill_valid_in) busy_next[kill_reg_in] = 1'b0;
        if (writeback_valid_in) busy_next[writeback_reg_in] = 1'b0;
    end

    RXVDFF #(
        .width(num_phys_regs)
    ) busy_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (busy_next),
        .q    (busy_out)
    );

endmodule
