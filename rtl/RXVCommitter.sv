`default_nettype none

import RXVTypes::commit_entry;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::commit_width;
import RXVTrace::trace_end_instruction;
import RXVTrace::trace_exception;
import RXVCSR::mtvec_t;
import RXVCSR::mtvec_dest;

module RXVCommitter (
    input  logic        clk,
    input  logic        reset,
    // Commit buffer
    input  logic        commit_empty,
    // verilator lint_off UNUSED
    input  commit_entry commit_in,
    // verilator lint_on UNUSED
    input  logic        commit_complete,
    input  logic        commit_killed,
    input  logic        commit_excepted,
    output logic        commit_valid,
    output logic        retired,
    // To rename file
    output renamed_reg  commit_rename_out,
    output logic        commit_rename_valid,
    output logic        commit_rename_rollback,
    // To register allocator
    output logic        commit_reg_push,
    output phys_reg_tag commit_reg_reg,
    // Exception handling
    input  logic        exception_pending,
    output logic        exception_resteer,
    output logic        exception_priv_change
);

    logic commit_ready;
    logic exception_resteer_next;
    logic killed;

    always_comb begin
        killed = commit_killed | exception_cleanup;
    end

    always_comb begin
        commit_ready = ~commit_empty & (commit_complete | commit_killed | commit_excepted);
    end

    always_comb begin
        retired = commit_ready & (~killed | commit_excepted);
    end

    always_comb begin
        commit_rename_out      = commit_in.dest_reg;
        commit_rename_valid    = 1'b0;
        commit_rename_rollback = 1'b0;

        if (!commit_empty && commit_complete && commit_in.have_rename &&
            |commit_in.dest_reg.arch && !killed) begin
            commit_rename_valid = 1'b1;
        end

        if (!commit_empty && commit_excepted) begin
            commit_rename_rollback = 1'b1;
        end
    end

    always_comb begin
        commit_reg_reg = commit_in.stale_phys;

        if (!commit_empty && (commit_excepted || killed)) commit_reg_reg = commit_in.dest_reg.phys;

        commit_reg_push = commit_ready & |commit_reg_reg;
    end

    always_comb begin
        commit_valid = !commit_empty && commit_ready;
    end

    always_comb begin
        exception_resteer_next = commit_empty && exception_pending;
    end

    always_comb begin
        exception_priv_change = exception_resteer_next;
    end

    RXVDFF exception_resteer_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exception_resteer_next),
        .q    (exception_resteer)
    );

endmodule
