`default_nettype none

import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_uop;
import RXVTypes::commit_width;
import RXVCSR::RXVException;
import RXVCSR::mstatus_t;
import RXVCSR::privilege_t;
import RXVMMU::translation_t;
import RXVMMU::asid_bits;
import RXVMMU::tlb_inv_op;

module RXVLSUWrapper #(
    parameter nr_lines        = 4,
    parameter nr_ways         = 4,
    parameter line_size_bytes = 16
) (
    input  logic                           clk,
    input  logic                           reset,
    input  logic                           icache_busy,
    output logic                           icache_invalidate,
    // From decode
    input  logic                           kill_valid,
    input  logic                           exec_valid,
    input  logic                           exec_have_writeback,
    input  phys_reg_tag                    exec_rd,
    input  logic        [commit_width-1:0] exec_id,
    input  logic        [            31:0] op1,
    input  logic        [            31:0] op2,
    input  logic        [            31:0] exec_immed,
    input  logic        [            31:2] exec_pc,
    input  logic        [            31:2] exec_next_pc,
    input  rxv_uop                         exec_uop,
    // Decode stall feedback, only set on cache-miss or uncached access where
    // it becomes a variable latency access
    output logic                           lsu_busy,
    // Result
    input  logic                           lsu_reg_busy,
    output phys_reg_tag                    lsu_reg_addr,
    output logic                           lsu_reg_wr_en,
    output logic        [            31:0] lsu_reg_wr_data,
    output logic                           lsu_complete,
    output logic        [commit_width-1:0] lsu_complete_id,
    // Exception handling
    input  privilege_t                     current_privilege,
    input  mstatus_t                       mstatus,
    output RXVException                    lsu_exception,
    output logic        [commit_width-1:0] lsu_except_id,
    output logic                           lsu_busy_kill,
    output logic                           lsu_resteer,
    output logic        [            31:2] lsu_resteer_tgt,
    output logic                           global_stall_start,
    output logic                           global_stall_end,
    // TLB
    input  logic        [           31:12] tlb_pa,
    input  logic                           tlb_dirty,
    input  logic                           tlb_accessed,
    input  logic                           tlb_page_global,
    input  logic                           tlb_user,
    input  logic                           tlb_exec,
    input  logic                           tlb_write,
    input  logic                           tlb_read,
    input  logic                           tlb_valid,
    input  logic        [   asid_bits-1:0] tlb_asid,
    input  logic                           tlb_busy,
    output tlb_inv_op                      lsu_tlb_inv_op,
    output logic        [   asid_bits-1:0] lsu_tlb_inv_asid,
    output logic        [           31:12] lsu_tlb_inv_addr,
    input  logic                           lsu_tlb_enabled,
    // Cache snoop signals
    output logic        [            31:2] dcache_address,
    output logic                           dcache_valid
);

    logic                dcache_busy;
    logic         [31:0] dcache_rdata;
    logic                dcache_wren;
    logic         [ 3:0] dcache_bytesel;
    logic         [31:0] dcache_wdata;
    logic                dcache_invalidate;
    logic                dcache_clean;
    logic                dcache_phys_valid;
    // verilator lint_off UNUSED
    logic         [31:2] dcache_phys_in;
    logic         [31:2] dcache_phys_out;
    // verilator lint_on UNUSED
    logic                dcache_device_memory;
    translation_t        lsu_translation;

    MemInterface mem_bus ();

    BusTransactor BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVDCache #(
        .nr_lines       (nr_lines),
        .nr_ways        (nr_ways),
        .line_size_bytes(line_size_bytes)
    ) RXVDCache (
        .clk          (clk),
        .reset        (reset),
        .address      (dcache_address),
        .valid        (dcache_valid),
        .busy         (dcache_busy),
        .din          (dcache_wdata),
        .wren         (dcache_wren),
        .bytesel      (dcache_bytesel),
        .dout         (dcache_rdata),
        .invalidate   (dcache_invalidate),
        .clean        (dcache_clean),
        .bus          (mem_bus.Manager),
        .phys_in      (dcache_phys_in),
        .phys_valid   (dcache_phys_valid),
        .phys_out     (dcache_phys_out),
        .device_memory(dcache_device_memory)
    );

    RXVLSU RXVLSU (
        .clk         (clk),
        .reset       (reset),
        .dcache_phys (dcache_phys_in),
        .lsu_tlb_busy(tlb_busy),
        .*
    );

    always_comb begin
        dcache_device_memory = &dcache_phys_out[31:28];
    end

    always_comb begin
        lsu_translation.pa          = tlb_pa;
        lsu_translation.dirty       = tlb_dirty;
        lsu_translation.accessed    = tlb_accessed;
        lsu_translation.page_global = tlb_page_global;
        lsu_translation.user        = tlb_user;
        lsu_translation.exec        = tlb_exec;
        lsu_translation.write       = tlb_write;
        lsu_translation.read        = tlb_read;
        lsu_translation.valid       = tlb_valid;
        lsu_translation.asid        = tlb_asid;
    end

endmodule
