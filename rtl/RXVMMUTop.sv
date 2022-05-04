`default_nettype none

import RXVMMU::sv32_pte_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;

module RXVMMUTop #(
    parameter int num_d_entries = 8,
    parameter int num_i_entries = 8
) (
    input  logic                         clk,
    input  logic                         reset,
    // Control
    input  logic         [        31:12] translation_base,
    // To/from LSU
    input  logic         [        31:12] d_va,
    input  logic                         d_valid,
    input  logic                         d_enabled,
    output logic                         d_busy,
    output translation_t                 d_translation,
    input  logic         [asid_bits-1:0] active_asid,
    input  tlb_inv_op                    tlb_op,
    input  logic         [asid_bits-1:0] inv_asid,
    input  logic         [        31:12] inv_addr,
    // To/from fetch
    input  logic         [        31:12] i_va,
    input  logic                         i_valid,
    input  logic                         i_enabled,
    output logic                         i_busy,
    output translation_t                 i_translation,
    // To/from cache
    output logic         [         31:2] dcache_address,
    output logic                         dcache_valid,
    input  logic                         dcache_busy,
    input  logic         [         31:0] dcache_rdata
);

    logic      [31:12] d_walk_va;
    logic              d_walk_valid;
    logic              d_walk_busy;
    logic              d_walk_grant;
    logic      [31:12] i_walk_va;
    logic              i_walk_valid;
    logic              i_walk_busy;
    logic              i_walk_grant;
    logic      [31:12] walk_va;
    logic              walk_valid;
    logic              walk_busy;
    logic              walk_hold;
    sv32_pte_t         walk_pte;
    logic              walk_is_megapage;
    logic              walk_translation_error;

    RXVTLB #(
        .num_entries(num_d_entries)
    ) DTLB (
        .clk                   (clk),
        .reset                 (reset),
        .va                    (d_va),
        .active_asid           (active_asid),
        .valid                 (d_valid),
        .grant                 (d_walk_grant),
        .translation           (d_translation),
        .busy                  (d_busy),
        .tlb_op                (tlb_op),
        .inv_asid              (inv_asid),
        .inv_addr              (inv_addr),
        .walk_va               (d_walk_va),
        .walk_valid            (d_walk_valid),
        .walk_busy             (d_walk_busy),
        .walk_pte              (walk_pte),
        .walk_is_megapage      (walk_is_megapage),
        .walk_translation_error(walk_translation_error),
        .enabled               (d_enabled)
    );

    RXVTLB #(
        .num_entries(num_i_entries)
    ) ITLB (
        .clk                   (clk),
        .reset                 (reset),
        .va                    (i_va),
        .active_asid           (active_asid),
        .valid                 (i_valid),
        .grant                 (i_walk_grant),
        .translation           (i_translation),
        .busy                  (i_busy),
        .tlb_op                (tlb_op),
        .inv_asid              (inv_asid),
        .inv_addr              (inv_addr),
        .walk_va               (i_walk_va),
        .walk_valid            (i_walk_valid),
        .walk_busy             (i_walk_busy),
        .walk_pte              (walk_pte),
        .walk_is_megapage      (walk_is_megapage),
        .walk_translation_error(walk_translation_error),
        .enabled               (i_enabled)
    );

    RXVPTWalker RXVPTWalker (
        .clk              (clk),
        .reset            (reset),
        .va               (walk_va),
        .valid            (walk_valid),
        .translation_base (translation_base),
        .busy             (walk_busy),
        .pte_out          (walk_pte),
        .is_megapage      (walk_is_megapage),
        .translation_error(walk_translation_error),
        .dcache_address   (dcache_address),
        .dcache_valid     (dcache_valid),
        .dcache_busy      (dcache_busy),
        .dcache_rdata     (dcache_rdata)
    );

    StaticArbiter #(
        .width(2)
    ) TLBArb (
        .clk    (clk),
        .reset  (reset),
        .request({i_walk_valid, d_walk_valid}),
        .hold   (walk_hold),
        .grant  ({i_walk_grant, d_walk_grant})
    );

    always_comb begin
        walk_hold   = walk_busy;

        walk_va     = d_walk_grant ? d_walk_va : i_walk_va;
        walk_valid  = d_walk_grant ? d_walk_valid : i_walk_valid;
        d_walk_busy = d_walk_grant ? walk_busy : 1'b0;
        i_walk_busy = i_walk_grant ? walk_busy : 1'b0;
    end

endmodule
