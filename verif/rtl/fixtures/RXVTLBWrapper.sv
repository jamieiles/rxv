`default_nettype none

import RXVMMU::sv32_pte_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;

module RXVTLBWrapper (
    input  logic                         clk,
    input  logic                         reset,
    // To/from fetch/LSU
    input  logic         [        31:12] va,
    input  logic         [asid_bits-1:0] active_asid,
    input  logic                         valid,
    output translation_t                 translation,
    output logic                         busy,
    input  tlb_inv_op                    tlb_op,
    input  logic         [asid_bits-1:0] inv_asid,
    input  logic         [        31:12] inv_addr,
    input  logic         [        31:12] walk_translation_base,
    input  logic                         enabled,
    input  logic                         dcache_invalidate,
    output logic                         dcache_busy
);

    logic              dcache_valid;
    logic      [ 31:0] dcache_dout;
    logic      [ 31:2] dcache_address;

    logic      [31:12] walk_va;
    logic              walk_valid;
    logic              walk_busy;
    sv32_pte_t         walk_pte;
    logic              walk_is_megapage;
    logic              walk_translation_error;

    MemInterface mem_bus ();

    BusTransactor BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVDCache RXVDCache (
        .clk          (clk),
        .reset        (reset),
        .address      (dcache_address),
        .valid        (dcache_valid),
        .busy         (dcache_busy),
        .din          (32'b0),
        .wren         (1'b0),
        .bytesel      (4'b1111),
        .dout         (dcache_dout),
        .invalidate   (dcache_invalidate),
        .clean        (1'b0),
        .bus          (mem_bus.Manager),
        // verilator lint_off PINCONNECTEMPTY
        .phys_out     (),
        // verilator lint_on PINCONNECTEMPTY
        .device_memory(1'b0)
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
        .dcache_address   (dcache_address),
        .dcache_valid     (dcache_valid),
        .dcache_busy      (dcache_busy),
        .dcache_rdata     (dcache_dout)
    );

    RXVTLB RXVTLB (.*);

endmodule
