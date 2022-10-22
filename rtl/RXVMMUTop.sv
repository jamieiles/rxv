`include "RXV.svh"

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
    output logic                         d_access_fault,
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
    output logic                         i_access_fault,
    // To/from cache
    output logic         [         31:2] dcache_address,
    output logic                         dcache_valid,
    input  logic                         dcache_busy,
    input  logic         [         31:0] dcache_rdata,
    output logic         [         31:2] dcache_phys_in,
    output logic                         dcache_phys_valid,
    input  logic                         dcache_grant,
    // To PMP
    output logic         [         31:2] d_pmp_addr,
    input  pmp_perms                     d_pmp,
    output logic         [         31:2] i_pmp_addr,
    input  pmp_perms                     i_pmp,
    // PMU
    output logic                         pmu_itlb_access,
    output logic                         pmu_itlb_miss,
    output logic                         pmu_dtlb_access,
    output logic                         pmu_dtlb_miss,
    // Prioritisation
    input  logic                         lsu_busy
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
    logic              walk_pmp_violation;
    logic              i_walk_lsu_gated;
    logic      [ 31:2] walk_pmp_addr;
    logic      [ 31:2] dtlb_pmp_addr;

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
        .access_fault          (d_access_fault),
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
        .walk_pmp_violation    (walk_pmp_violation),
        .phys_addr             (dtlb_pmp_addr),
        .phys_perms            (d_pmp),
        .pmu_tlb_access        (pmu_dtlb_access),
        .pmu_tlb_miss          (pmu_dtlb_miss),
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
        .access_fault          (i_access_fault),
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
        .walk_pmp_violation    (walk_pmp_violation),
        .phys_addr             (i_pmp_addr),
        .phys_perms            (i_pmp),
        .pmu_tlb_access        (pmu_itlb_access),
        .pmu_tlb_miss          (pmu_itlb_miss),
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
        .pmp_violation    (walk_pmp_violation),
        .dcache_address   (dcache_address),
        .dcache_valid     (dcache_valid),
        .dcache_busy      (dcache_busy),
        .dcache_rdata     (dcache_rdata),
        .dcache_phys_in   (dcache_phys_in),
        .dcache_phys_valid(dcache_phys_valid),
        .dcache_grant     (dcache_grant),
        .pmp_addr         (walk_pmp_addr),
        .pmp              (d_pmp)
    );

    StaticArbiter #(
        .width(2)
    ) TLBArb (
        .clk    (clk),
        .reset  (reset),
        .request({i_walk_lsu_gated, d_walk_valid}),
        .hold   (walk_hold),
        .grant  ({i_walk_grant, d_walk_grant})
    );

    always_comb begin
        walk_hold        = walk_busy;

        i_walk_lsu_gated = i_walk_valid & ~lsu_busy;

        walk_va          = d_walk_grant ? d_walk_va : i_walk_va;
        walk_valid       = d_walk_grant ? d_walk_valid : i_walk_grant ? i_walk_valid : 1'b0;
        d_walk_busy      = d_walk_grant ? walk_busy : 1'b0;
        i_walk_busy      = i_walk_grant ? walk_busy : 1'b0;

        d_pmp_addr       = d_walk_grant || i_walk_grant ? walk_pmp_addr : dtlb_pmp_addr;
    end

endmodule
