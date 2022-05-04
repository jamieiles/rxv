`default_nettype none

import RXVMMU::sv32_pte_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;

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
    output logic                         dcache_busy
);

    logic        dcache_valid;
    logic [31:0] dcache_dout;
    logic [31:2] dcache_address;

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

    RXVMMUTop RXVMMUTop (
        .dcache_rdata(dcache_dout),
        .*
    );

endmodule
