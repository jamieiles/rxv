import RXVTypes::renamed_reg;

module RXVRenameFileWrapper (
    input  logic                     clk,
    input  logic                     reset,
    // Rename request
    input  logic [arch_reg_bits-1:0] rename_in_arch,
    input  logic [phys_reg_bits-1:0] rename_in_phys,
    input  logic                     rename_valid,
    output logic [phys_reg_bits-1:0] stale_phys_reg,
    // Rename lookup
    input  logic [arch_reg_bits-1:0] lookup_tag_in [1:0],
    output logic [phys_reg_bits-1:0] lookup_tag_out[1:0],
    // Commit
    input  logic [arch_reg_bits-1:0] commit_in_arch,
    input  logic [phys_reg_bits-1:0] commit_in_phys,
    input  logic                     commit_valid,
    // Rollback
    input  logic                     rollback,
    input  logic                     kill,
    input  logic                     lsu_busy_kill
);

    renamed_reg rename_in;
    renamed_reg commit_in;

    assign rename_in.arch = rename_in_arch;
    assign rename_in.phys = rename_in_phys;
    assign commit_in.arch = commit_in_arch;
    assign commit_in.phys = commit_in_phys;

    RXVRenameFile RXVRenameFile (
        .clk           (clk),
        .reset         (reset),
        .rename_in     (rename_in),
        .rename_valid  (rename_valid),
        .stale_phys_reg(stale_phys_reg),
        .lookup_tag_in (lookup_tag_in),
        .lookup_tag_out(lookup_tag_out),
        .commit_in     (commit_in),
        .commit_valid  (commit_valid),
        .rollback      (rollback),
        .kill          (kill),
        .lsu_busy_kill (lsu_busy_kill)
    );

endmodule
