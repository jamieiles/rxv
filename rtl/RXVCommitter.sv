`default_nettype none

import RXVTypes::commit_entry;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;

module RXVCommitter (
    input  logic              clk,
    // Commit buffer
    input  logic              commit_empty,
    input  commit_entry       commit_in,
    input  logic              commit_complete,
    input  logic              commit_killed,
    input  logic              commit_excepted,
    output logic              commit_valid,
    input  logic        [2:0] commit_id,
    // To rename file
    output renamed_reg        commit_rename_out,
    output logic              commit_rename_valid,
    output logic              commit_rename_rollback,
    // To register allocator
    output logic              commit_reg_push,
    output phys_reg_tag       commit_reg_reg
);

    logic commit_ready;

    always_comb begin
        commit_ready = ~commit_empty & (commit_complete | commit_killed | commit_excepted);
    end

    always_comb begin
        commit_rename_out      = commit_in.dest_reg;
        commit_rename_valid    = 1'b0;
        commit_rename_rollback = 1'b0;

        if (!commit_empty && commit_complete && commit_in.have_writeback) begin
            commit_rename_valid = 1'b1;
        end

        if (!commit_empty && (commit_killed || commit_excepted)) begin
            commit_rename_rollback = 1'b1;
        end
    end

    always_comb begin
        commit_reg_reg = commit_in.stale_phys;

        if (!commit_empty && commit_complete) commit_reg_reg = commit_in.stale_phys;
        if (!commit_empty && (commit_excepted || commit_killed))
            commit_reg_reg = commit_in.dest_reg.phys;

        commit_reg_push = commit_ready & |commit_reg_reg;
    end

    always_comb begin
        commit_valid = !commit_empty && commit_ready;
    end

    always_ff @(posedge clk) begin
        if (commit_valid) begin
            trace_end_instruction(32'(commit_id));
        end
    end

endmodule
