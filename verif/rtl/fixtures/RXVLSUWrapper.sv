`default_nettype none

import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_uop;
import RXVTypes::commit_width;
import RXVCSR::RXVException;

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
    output RXVException                    lsu_exception,
    output logic        [commit_width-1:0] lsu_except_id,
    output logic                           lsu_busy_kill,
    output logic                           lsu_resteer,
    output logic        [            31:2] lsu_resteer_tgt,
    output logic                           global_stall_start,
    output logic                           global_stall_end
);

    logic [31:2] dcache_address;
    logic        dcache_valid;
    logic        dcache_busy;
    logic [31:0] dcache_rdata;
    logic        dcache_wren;
    logic [ 3:0] dcache_bytesel;
    logic [31:0] dcache_wdata;
    logic        dcache_invalidate;
    logic        dcache_clean;
    logic        dcache_phys_valid;
    // verilator lint_off UNUSED
    logic [31:2] dcache_phys_in;
    logic [31:2] dcache_phys_out;
    // verilator lint_on UNUSED
    logic        dcache_device_memory;

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
        .clk        (clk),
        .reset      (reset),
        .dcache_phys(dcache_phys_in),
        .*
    );

    always_comb begin
        dcache_device_memory = &dcache_phys_out[31:28];
    end

endmodule
