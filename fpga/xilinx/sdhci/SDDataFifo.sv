// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// Single block (512 byte) data buffer between the data engine and the
// buffer data port.
//
// The buffer is a FIFO of 32-bit words, the direction is fixed for each
// transfer: the data engine fills it and the CPU drains it for reads and
// vice versa for writes.  Block level status is derived here:
//
//   buf_rd_en: Buffer Read Enable, a received block has been checked and is
//              ready to be read, cleared once it has been drained.
//   buf_wr_en: Buffer Write Enable, the buffer is empty and the CPU still
//              has blocks to write.
//   blk_avail: a whole block has been written by the CPU and can be sent.
module SDDataFifo (
    input  logic        clk,
    input  logic        reset,
    // Transfer configuration, latched on xfer_start
    input  logic        xfer_start,
    input  logic        tm_read,
    input  logic        tm_multi,
    input  logic        tm_bce,
    input  logic [15:0] blkcnt,
    input  logic [ 9:0] blksz,
    input  logic        read_active,
    input  logic        write_active,
    // Data engine
    input  logic        eng_push,
    input  logic [31:0] eng_wdata,
    input  logic        eng_pop,
    input  logic        eng_blk_done,
    // CPU
    input  logic        cpu_push,
    input  logic [31:0] cpu_wdata,
    input  logic        cpu_pop,
    output logic [31:0] rdata,
    // Status
    output logic        empty,
    output logic        blk_avail,
    output logic        buf_rd_en,
    output logic        buf_wr_en
);

    logic [31:0] mem                 [128];
    logic [ 6:0] wr_ptr;
    logic [ 6:0] rd_ptr;
    logic [ 7:0] count;
    logic [ 7:0] count_next;
    logic [ 7:0] block_words;
    logic        x_read;
    logic        x_infinite;
    logic [16:0] cpu_blocks_left;
    logic        blk_ready;
    logic        push;
    logic        pop;
    logic [31:0] wdata;
    logic        cpu_blk_written;

    always_comb begin
        push = x_read ? eng_push : cpu_push;
        pop = x_read ? cpu_pop : eng_pop;
        wdata = x_read ? eng_wdata : cpu_wdata;

        // Never overflow or underflow: the engine only pushes into an empty
        // buffer and stray CPU accesses are dropped.
        if (count == 8'd128) push = 1'b0;
        if (count == 8'd0) pop = 1'b0;

        count_next = count + 8'(push) - 8'(pop);
        cpu_blk_written = !x_read && push && count_next == block_words;

        rdata = mem[rd_ptr];
        empty = count == 8'd0;
        blk_avail = !x_read && count == block_words;
        buf_rd_en = read_active && blk_ready;
        buf_wr_en = write_active && empty && (x_infinite || |cpu_blocks_left);
    end

    always_ff @(posedge clk) begin
        if (push) mem[wr_ptr] <= wdata;
    end

    always_ff @(posedge clk) begin
        if (push) wr_ptr <= wr_ptr + 1'b1;
        if (pop) rd_ptr <= rd_ptr + 1'b1;
        count <= count_next;

        if (eng_blk_done && x_read) blk_ready <= 1'b1;
        if (pop && count == 8'd1) blk_ready <= 1'b0;

        if (cpu_blk_written && !x_infinite) cpu_blocks_left <= cpu_blocks_left - 1'b1;

        if (xfer_start) begin
            x_read          <= tm_read;
            x_infinite      <= tm_multi && !tm_bce;
            cpu_blocks_left <= tm_multi ? {1'b0, blkcnt} : 17'd1;
            block_words     <= 8'((11'(blksz) + 11'd3) >> 2);
        end

        if (reset || xfer_start) begin
            wr_ptr    <= 7'b0;
            rd_ptr    <= 7'b0;
            count     <= 8'b0;
            blk_ready <= 1'b0;
        end

        if (reset) begin
            x_read          <= 1'b0;
            x_infinite      <= 1'b0;
            cpu_blocks_left <= 17'b0;
            block_words     <= 8'd128;
        end
    end

endmodule
