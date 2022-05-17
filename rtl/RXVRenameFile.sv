`default_nettype none

import RXVTypes::arch_reg_tag;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::num_arch_regs;
import RXVTypes::num_phys_regs;
import RXVTypes::arch_reg_bits;
import RXVTypes::phys_reg_bits;

module RXVRenameFile (
    input  logic        clk,
    input  logic        reset,
    // Rename request
    input  renamed_reg  rename_in,
    input  logic        rename_valid,
    output phys_reg_tag stale_phys_reg,
    // Rename lookup
    input  arch_reg_tag lookup_tag_in [1:0],
    output phys_reg_tag lookup_tag_out[1:0],
    // Commit
    input  renamed_reg  commit_in,
    input  logic        commit_valid,
    // Rollback
    input  logic        rollback,
    input  logic        kill,
    input  logic        lsu_busy_kill
);

    typedef struct packed {
        renamed_reg renamed;
        phys_reg_tag stale;
        logic valid;
    } rename_record;

    logic           [num_arch_regs-1:0]                   commit_masked;
    logic           [num_arch_regs-1:0]                   commit_encoded;
    logic           [num_arch_regs-1:0]                   rename_masked;
    logic           [num_arch_regs-1:0]                   rename_encoded;
    logic           [num_arch_regs-1:0]                   last_rename_encoded[0:1];

    phys_reg_tag  [                    num_arch_regs-1:0] commit_map;
    phys_reg_tag  [                    num_arch_regs-1:0] latest_map;
    phys_reg_tag  [                    num_arch_regs-1:0] latest_next;

    rename_record                                         last_rename        [0:1];
    rename_record                                         last_rename_next   [0:1];

    OneHotEncode #(
        .width(num_arch_regs)
    ) commit_en_encode (
        .d(commit_in.arch),
        .q(commit_encoded)
    );

    OneHotEncode #(
        .width(num_arch_regs)
    ) rename_en_encode (
        .d(rename_in.arch),
        .q(rename_encoded)
    );

    OneHotEncode #(
        .width(num_arch_regs)
    ) kill_en_encode_0 (
        .d(last_rename[0].renamed.arch),
        .q(last_rename_encoded[0])
    );

    OneHotEncode #(
        .width(num_arch_regs)
    ) kill_en_encode_1 (
        .d(last_rename[1].renamed.arch),
        .q(last_rename_encoded[1])
    );

    genvar i;
    generate
        for (i = 0; i < num_arch_regs; i = i + 1) begin : gen_reg_map
            RXVDFF #(
                .width(phys_reg_bits)
            ) commit_map_dff (
                .clk  (clk),
                .reset(reset),
                .en   (commit_masked[i]),
                .d    (commit_in.phys),
                .q    (commit_map[i])
            );

            RXVDFF #(
                .width(phys_reg_bits)
            ) latest_map_dff (
                .clk  (clk),
                .reset(reset),
                .en   (rename_masked[i]),
                .d    (latest_next[i]),
                .q    (latest_map[i])
            );
        end
    endgenerate

    always_comb begin
        commit_masked = commit_encoded & {num_arch_regs{commit_valid}};
    end

    always_comb begin
        rename_masked = (rename_encoded & {num_arch_regs{rename_valid}});
        if (lsu_busy_kill | kill) begin
            rename_masked = 'b0;
            if (lsu_busy_kill && last_rename[0].valid) rename_masked |= last_rename_encoded[0];
            if ((kill || lsu_busy_kill) && last_rename[1].valid)
                rename_masked |= last_rename_encoded[1];
        end
        if (rollback) rename_masked = {num_arch_regs{1'b1}};
    end

    always_comb begin
        last_rename_next[1].renamed = rename_in;
        last_rename_next[1].stale   = stale_phys_reg;
        last_rename_next[1].valid   = rename_valid;
        last_rename_next[0].renamed = last_rename[1].renamed;
        last_rename_next[0].stale   = last_rename[1].stale;
        last_rename_next[0].valid   = last_rename[1].valid;
    end

    always_comb begin
        integer j;

        for (j = 0; j < num_arch_regs; j = j + 1) begin
            latest_next[j] = rollback ? commit_map[j] : rename_in.phys;
        end
        if (kill && last_rename[1].valid)
            latest_next[last_rename[1].renamed.arch] = last_rename[1].stale;
        if (lsu_busy_kill && last_rename[0].valid)
            latest_next[last_rename[0].renamed.arch] = last_rename[0].stale;
    end

    RXVAssert no_rename_during_kill (
        .clk      (clk),
        .en       (kill),
        .condition(!rename_valid)
    );

    always_comb begin
        lookup_tag_out[0] = latest_map[lookup_tag_in[0]];
        lookup_tag_out[1] = latest_map[lookup_tag_in[1]];
    end

    always_comb begin
        stale_phys_reg = latest_map[rename_in.arch];
    end

    RXVDFF #(
        .width($bits(last_rename[0]))
    ) last_rename_0_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (last_rename_next[0]),
        .q    (last_rename[0])
    );

    RXVDFF #(
        .width($bits(last_rename[1]))
    ) last_rename_1_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (last_rename_next[1]),
        .q    (last_rename[1])
    );

    RXVAssert no_rename_x0 (
        .clk      (clk),
        .en       (rename_valid),
        .condition(rename_in.arch != 0)
    );

endmodule
