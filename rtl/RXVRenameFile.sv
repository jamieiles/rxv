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
    input  logic        rollback
);

    logic          [num_arch_regs-1:0]                   commit_masked;
    logic          [num_arch_regs-1:0]                   commit_encoded;
    logic          [num_arch_regs-1:0]                   rename_masked;
    logic          [num_arch_regs-1:0]                   rename_encoded;

    phys_reg_tag [                    num_arch_regs-1:0] commit_map;
    phys_reg_tag [                    num_arch_regs-1:0] latest_map;
    phys_reg_tag [                    num_arch_regs-1:0] latest_next;

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
        rename_masked = rollback ? {num_arch_regs{1'b1}} :
            (rename_encoded & {num_arch_regs{rename_valid}});
    end

    always_comb begin
        integer j;

        for (j = 0; j < num_arch_regs; j = j + 1) begin
            latest_next[j] = rollback ? commit_map[j] : rename_in.phys;
        end
    end

    always_comb begin
        lookup_tag_out[0] = latest_map[lookup_tag_in[0]];
        lookup_tag_out[1] = latest_map[lookup_tag_in[1]];
    end

    always_comb begin
        stale_phys_reg = latest_map[rename_in.arch];
    end

`ifdef verilator
    always_ff @(posedge clk) begin
        if (rename_valid) assert (rename_in.arch != 0);
    end
`endif

endmodule
