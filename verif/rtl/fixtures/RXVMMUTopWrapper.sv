`include "RXV.svh"

import RXVMMU::sv32_pte_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;
import RXVMMU::pmp_perms;

module RXVMMUTopWrapper (
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
    input  logic                         dcache_invalidate,
    output logic                         dcache_busy,
    input  logic                         lsu_busy,
    output logic                         d_access_fault,
    output logic                         i_access_fault,
    output logic                         pmu_itlb_access,
    output logic                         pmu_itlb_miss,
    output logic                         pmu_dtlb_access,
    output logic                         pmu_dtlb_miss
);

    logic            dcache_valid;
    logic     [31:0] dcache_dout;
    logic     [31:2] dcache_address;
    logic     [31:2] dcache_phys_in;
    logic            dcache_phys_valid;
    logic            dcache_grant;
    pmp_perms        d_pmp;
    pmp_perms        i_pmp;

    always_comb dcache_grant = 1'b1;
    always_comb d_pmp = 3'b111;
    always_comb i_pmp = 3'b111;

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

    RXVMMUTop RXVMMUTop (
        .dcache_rdata(dcache_dout),
        // verilator lint_off PINCONNECTEMPTY
        .d_pmp_addr  (),
        .i_pmp_addr  (),
        // verilator lint_on PINCONNECTEMPTY
        .*
    );

endmodule
