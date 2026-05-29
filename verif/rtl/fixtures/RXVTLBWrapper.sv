// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVMMU::sv32_pte_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;
import RXVMMU::pmp_perms;

module RXVTLBWrapper (
    input  logic                         clk,
    input  logic                         reset,
    // To/from fetch/LSU
    input  logic         [        31:12] va,
    input  logic         [asid_bits-1:0] active_asid,
    input  logic                         valid,
    input  logic                         grant,
    output translation_t                 translation,
    output logic                         access_fault,
    output logic                         busy,
    input  tlb_inv_op                    tlb_op,
    input  logic         [asid_bits-1:0] inv_asid,
    input  logic         [        31:12] inv_addr,
    input  logic         [        31:12] walk_translation_base,
    output logic                         walk_valid_req,         // For test inspection
    input  logic                         enabled,
    input  logic                         dcache_invalidate,
    output logic                         dcache_busy,
    // PMU
    output logic                         pmu_tlb_access,
    output logic                         pmu_tlb_miss
);

    logic              dcache_valid;
    logic      [ 31:0] dcache_dout;
    logic      [ 31:2] dcache_address;
    logic      [ 31:2] dcache_phys_in;
    logic              dcache_phys_valid;

    logic      [31:12] walk_va;
    logic              walk_busy;
    sv32_pte_t         walk_pte;
    logic              walk_is_megapage;
    logic              walk_translation_error;
    logic              walk_valid;
    logic              walk_pmp_violation;

    pmp_perms          walk_pmp;
    pmp_perms          tlb_pmp;

    always_comb walk_pmp = 3'b111;
    always_comb tlb_pmp = 3'b111;

    MemInterface mem_bus ();

    BusTransactor BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVDCache RXVDCache (
        .clk                 (clk),
        .reset               (reset),
        .address             (dcache_address),
        .valid               (dcache_valid),
        .busy                (dcache_busy),
        .din                 (32'b0),
        .wren                (1'b0),
        .bytesel             (4'b1111),
        .dout                (dcache_dout),
        .invalidate          (dcache_invalidate),
        .clean               (1'b0),
        .bus                 (mem_bus.Manager),
        .phys_in             (dcache_phys_in),
        .phys_valid          (dcache_phys_valid),
        // verilator lint_off PINCONNECTEMPTY
        .phys_out            (),
        .pmu_dcache_wr_access(),
        .pmu_dcache_wr_miss  (),
        .pmu_dcache_rd_access(),
        .pmu_dcache_rd_miss  (),
        // verilator lint_on PINCONNECTEMPTY
        .device_memory       (1'b0)
    );

    RXVPTWalker RXVPTWalker (
        .clk              (clk),
        .reset            (reset),
        .va               (walk_va),
        .valid            (walk_valid),
        .translation_base (walk_translation_base),
        .busy             (walk_busy),
        .pte_out          (walk_pte),
        .is_megapage      (walk_is_megapage),
        .translation_error(walk_translation_error),
        .pmp_violation    (walk_pmp_violation),
        .dcache_address   (dcache_address),
        .dcache_valid     (dcache_valid),
        .dcache_busy      (dcache_busy),
        .dcache_rdata     (dcache_dout),
        .dcache_phys_in   (dcache_phys_in),
        .dcache_phys_valid(dcache_phys_valid),
        .dcache_grant     (1'b1),
        // verilator lint_off PINCONNECTEMPTY
        .pmp_addr         (),
        // verilator lint_on PINCONNECTEMPTY
        .pmp              (walk_pmp)
    );

    RXVTLB RXVTLB (
        .walk_valid(walk_valid_req),
        // verilator lint_off PINCONNECTEMPTY
        .phys_addr (),
        // verilator lint_on PINCONNECTEMPTY
        .phys_perms(tlb_pmp),
        .*
    );

    always_comb begin
        walk_valid = walk_valid_req & grant;
    end

endmodule
