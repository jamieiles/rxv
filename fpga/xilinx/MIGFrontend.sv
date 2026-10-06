// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
// Frontend for the Xilinx 7-series MIG native (app_*) interface.
//
// Normal memory is only ever accessed by the caches in whole, line-aligned
// bursts so there is no support for single accesses: every transaction is
// a full cache line.  With a 4:1 PHY and x16 DDR3 each app command transfers
// one BL8 burst of 128 bits so a line is beats_per_line commands.
//
// Reads: an AR is accepted from either port (alternating priority) and
// beats_per_line read commands are issued back-to-back.  The MIG returns
// read data in request order (ui_rd_data reorders) but has no backpressure
// so data lands in a FIFO that is credited at AR time.  The FIFO is unpacked
// to the requesting port at one 32-bit word per cycle.
//
// Writes: only the data port writes.  Words are packed into 128-bit beats
// and pushed into the MIG write data FIFO as soon as each beat is complete,
// with the command following once the data has been accepted (the MIG allows
// data ahead of the command).
//
// Ordering: the MIG bank machines retire requests to the same rank/bank in
// request order, and a line always falls in a single bank/row, so once
// commands have been issued same-line ordering is preserved.  Before issue we
// must ensure that a read of a line with write data still waiting for its
// commands is held off, and that a line's read commands are not split by
// write commands.
module MIGFrontend #(
    parameter int line_size_bytes = 64,
    parameter int app_addr_width  = 28,
    parameter int rd_fifo_order   = 4
) (
    input  logic                             clk,
    input  logic                             reset,
           MemInterface.Subordinate          ibus,
           MemInterface.Subordinate          dbus,
    input  logic                             init_calib_complete,
    output logic        [app_addr_width-1:0] app_addr,
    output logic        [               2:0] app_cmd,
    output logic                             app_en,
    input  logic                             app_rdy,
    output logic        [             127:0] app_wdf_data,
    output logic        [              15:0] app_wdf_mask,
    output logic                             app_wdf_wren,
    output logic                             app_wdf_end,
    input  logic                             app_wdf_rdy,
    input  logic        [             127:0] app_rd_data,
    input  logic                             app_rd_data_valid,
    // verilator lint_off UNUSED
    input  logic                             app_rd_data_end
    // verilator lint_on UNUSED
);

    localparam CMD_WRITE = 3'b000;
    localparam CMD_READ = 3'b001;

    localparam beats_per_line = line_size_bytes / 16;
    localparam beat_bits = $clog2(beats_per_line);
    localparam line_bits = $clog2(line_size_bytes);
    localparam line_addr_bits = app_addr_width - line_bits;
    localparam rd_fifo_depth = 1 << rd_fifo_order;
    localparam pq_order = $clog2(rd_fifo_depth / beats_per_line);
    localparam pq_depth = 1 << pq_order;
    localparam bus_len = 4'((line_size_bytes / 4) - 1);

    initial assert (beats_per_line >= 2 && (1 << beat_bits) == beats_per_line);
    initial assert (line_size_bytes <= 64);
    initial assert (pq_order >= 1);

    localparam PORT_I = 1'b0;
    localparam PORT_D = 1'b1;

    function [app_addr_width-1:0] beat_app_addr;
        input [line_addr_bits-1:0] line;
        input [beat_bits-1:0] beat;
        // app_addr is in units of the 16-bit DRAM word
        beat_app_addr = app_addr_width'({line, beat, 3'b000});
    endfunction

    // Read issue
    logic                        rd_issue_active;
    logic                        rd_issue_active_next;
    logic [       beat_bits-1:0] rd_issue_beat;
    logic [       beat_bits-1:0] rd_issue_beat_next;
    logic [  line_addr_bits-1:0] rd_issue_line;
    logic [  line_addr_bits-1:0] rd_issue_line_next;
    logic                        rd_last_port;
    logic                        rd_last_port_next;
    logic                        grant_i;
    logic                        grant_d;
    logic [  line_addr_bits-1:0] ar_line;
    logic                        rd_hazard;
    logic                        rd_credit_ok;
    logic                        issuer_free;
    logic                        ar_accept;
    logic [   rd_fifo_order:0] rd_credits;
    logic [   rd_fifo_order:0] rd_credits_next;
    logic                        rd_cmd_fire;
    logic                        wr_cmd_fire;

    // Read data
    logic [               127:0] rd_fifo                 [rd_fifo_depth];
    logic [   rd_fifo_order:0] rd_fifo_wr_ptr;
    logic [   rd_fifo_order:0] rd_fifo_rd_ptr;
    logic                        rd_fifo_empty;
    logic                        rd_fifo_pop;
    logic [               127:0] rd_fifo_head;
    logic                        pq                      [pq_depth];
    logic [          pq_order:0] pq_wr_ptr;
    logic [          pq_order:0] pq_rd_ptr;
    logic                        pq_pop;
    logic                        out_port;
    logic [                 1:0] out_word;
    logic [       beat_bits-1:0] out_beat;
    logic                        out_valid;
    logic                        out_ready;
    logic                        out_fire;
    logic [                31:0] out_data;
    logic                        out_last;

    // Write path
    logic                        wr_busy;
    logic                        wr_busy_next;
    logic [  line_addr_bits-1:0] wr_line;
    logic                        aw_accept;
    logic                        w_open;
    logic                        w_fire;
    logic                        wdf_fire;
    logic                        wr_words_done;
    logic                        wr_words_done_next;
    logic [                 1:0] wr_slot;
    logic [                 1:0] wr_word;
    logic [                 1:0] wr_word_next;
    logic                        wr_beat_valid;
    logic                        wr_beat_valid_next;
    logic [               127:0] wr_beat_data;
    logic [               127:0] wr_beat_data_next;
    logic [                15:0] wr_beat_mask;
    logic [                15:0] wr_beat_mask_next;
    logic [         beat_bits:0] wr_beats_written;
    logic [         beat_bits:0] wr_beats_written_next;
    logic [         beat_bits:0] wr_cmds_issued;
    logic [         beat_bits:0] wr_cmds_issued_next;
    logic                        wr_cmd_pending;
    logic                        wr_bvalid;
    logic                        wr_bvalid_next;

    // ------------------------------------------------------------------
    // Read address arbitration
    // ------------------------------------------------------------------
    always_comb begin
        // Alternate priority between the ports when both are requesting
        grant_d      = dbus.arvalid && (!ibus.arvalid || rd_last_port == PORT_I);
        grant_i      = ibus.arvalid && !grant_d;
        ar_line      = grant_d ? dbus.raddr[app_addr_width-1:line_bits] :
            ibus.raddr[app_addr_width-1:line_bits];

        rd_hazard    = wr_busy && ar_line == wr_line;
        rd_credit_ok = rd_credits + (rd_fifo_order + 1)'(beats_per_line) <=
            (rd_fifo_order + 1)'(rd_fifo_depth);
        // Don't change the presented command until any write command has
        // been accepted.
        issuer_free  = !rd_issue_active && (!wr_cmd_pending || app_rdy);
        ar_accept    = (grant_i || grant_d) && init_calib_complete && issuer_free &&
            !rd_hazard && rd_credit_ok;
    end

    assign ibus.arready = ar_accept && grant_i;
    assign dbus.arready = ar_accept && grant_d;

    // ------------------------------------------------------------------
    // Command issue: a read line owns the command port until all of its
    // commands have been accepted, writes fill the gaps.
    // ------------------------------------------------------------------
    always_comb begin
        wr_cmd_pending = wr_cmds_issued != wr_beats_written;

        if (rd_issue_active) begin
            app_en   = 1'b1;
            app_cmd  = CMD_READ;
            app_addr = beat_app_addr(rd_issue_line, rd_issue_beat);
        end else begin
            app_en   = wr_cmd_pending;
            app_cmd  = CMD_WRITE;
            app_addr = beat_app_addr(wr_line, wr_cmds_issued[beat_bits-1:0]);
        end

        rd_cmd_fire = rd_issue_active && app_rdy;
        wr_cmd_fire = !rd_issue_active && wr_cmd_pending && app_rdy;
    end

    always_comb begin
        rd_issue_active_next = rd_issue_active;
        rd_issue_beat_next   = rd_issue_beat;
        rd_issue_line_next   = rd_issue_line;
        rd_last_port_next    = rd_last_port;

        if (ar_accept) begin
            rd_issue_active_next = 1'b1;
            rd_issue_beat_next   = 'b0;
            rd_issue_line_next   = ar_line;
            rd_last_port_next    = grant_d;
        end else if (rd_cmd_fire) begin
            rd_issue_beat_next = rd_issue_beat + 1'b1;
            if (&rd_issue_beat) rd_issue_active_next = 1'b0;
        end

        rd_credits_next = rd_credits;
        if (ar_accept) rd_credits_next = rd_credits_next + (rd_fifo_order + 1)'(beats_per_line);
        if (rd_fifo_pop) rd_credits_next = rd_credits_next - 1'b1;
    end

    // ------------------------------------------------------------------
    // Read data: FIFO from the MIG, port queue recording the order in which
    // lines were requested, and the 128->32 unpacker.
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (app_rd_data_valid) rd_fifo[rd_fifo_wr_ptr[rd_fifo_order-1:0]] <= app_rd_data;
        if (ar_accept) pq[pq_wr_ptr[pq_order-1:0]] <= grant_d;
    end

    always_comb begin
        rd_fifo_empty = rd_fifo_wr_ptr == rd_fifo_rd_ptr;
        rd_fifo_head  = rd_fifo[rd_fifo_rd_ptr[rd_fifo_order-1:0]];
        out_port      = pq[pq_rd_ptr[pq_order-1:0]];
        out_valid     = !rd_fifo_empty;
        out_ready     = out_port == PORT_D ? dbus.rready : ibus.rready;
        out_fire      = out_valid && out_ready;
        out_data      = rd_fifo_head[{out_word, 5'b0}+:32];
        out_last      = &out_word && &out_beat;
        rd_fifo_pop   = out_fire && &out_word;
        pq_pop        = rd_fifo_pop && &out_beat;
    end

    assign ibus.rvalid = out_valid && out_port == PORT_I;
    assign dbus.rvalid = out_valid && out_port == PORT_D;
    assign ibus.rdata  = out_data;
    assign dbus.rdata  = out_data;
    assign ibus.rlast  = out_last;
    assign dbus.rlast  = out_last;

    RXVDFF #(
        .width(rd_fifo_order + 1)
    ) rd_fifo_wr_ptr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (app_rd_data_valid),
        .d    (rd_fifo_wr_ptr + 1'b1),
        .q    (rd_fifo_wr_ptr)
    );

    RXVDFF #(
        .width(rd_fifo_order + 1)
    ) rd_fifo_rd_ptr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (rd_fifo_pop),
        .d    (rd_fifo_rd_ptr + 1'b1),
        .q    (rd_fifo_rd_ptr)
    );

    RXVDFF #(
        .width(pq_order + 1)
    ) pq_wr_ptr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (ar_accept),
        .d    (pq_wr_ptr + 1'b1),
        .q    (pq_wr_ptr)
    );

    RXVDFF #(
        .width(pq_order + 1)
    ) pq_rd_ptr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (pq_pop),
        .d    (pq_rd_ptr + 1'b1),
        .q    (pq_rd_ptr)
    );

    RXVDFF #(
        .width(2)
    ) out_word_dff (
        .clk  (clk),
        .reset(reset),
        .en   (out_fire),
        .d    (out_word + 1'b1),
        .q    (out_word)
    );

    RXVDFF #(
        .width(beat_bits)
    ) out_beat_dff (
        .clk  (clk),
        .reset(reset),
        .en   (rd_fifo_pop),
        .d    (out_beat + 1'b1),
        .q    (out_beat)
    );

    // ------------------------------------------------------------------
    // Write path (data port only)
    // ------------------------------------------------------------------
    always_comb begin
        aw_accept    = dbus.awvalid && !wr_busy && init_calib_complete;
        // Accept data in the same cycle as the address
        w_open       = (wr_busy && !wr_words_done) || aw_accept;
        wdf_fire     = wr_beat_valid && app_wdf_rdy;
        wr_slot      = aw_accept ? 2'b0 : wr_word;
        w_fire       = dbus.wvalid && dbus.wready;
    end

    assign dbus.awready = !wr_busy && init_calib_complete;
    assign dbus.wready  = w_open && (!wr_beat_valid || app_wdf_rdy);
    assign dbus.bvalid  = wr_bvalid;

    assign app_wdf_data = wr_beat_data;
    assign app_wdf_mask = wr_beat_mask;
    assign app_wdf_wren = wr_beat_valid;
    assign app_wdf_end  = wr_beat_valid;

    always_comb begin
        wr_word_next          = wr_slot;
        wr_beat_data_next     = wr_beat_data;
        // Bytes not written are masked, a new beat starts fully masked
        wr_beat_mask_next     = wdf_fire || aw_accept ? 16'hffff : wr_beat_mask;
        wr_beat_valid_next    = wr_beat_valid && !wdf_fire;
        wr_words_done_next    = aw_accept ? 1'b0 : wr_words_done;

        if (w_fire) begin
            wr_beat_data_next[{wr_slot, 5'b0}+:32] = dbus.wdata;
            wr_beat_mask_next[{wr_slot, 2'b0}+:4]  = ~dbus.wstb;
            wr_word_next                           = wr_slot + 1'b1;
            if (&wr_slot || dbus.wlast) wr_beat_valid_next = 1'b1;
            if (dbus.wlast) begin
                wr_words_done_next = 1'b1;
                wr_word_next       = 2'b0;
            end
        end

        wr_beats_written_next = aw_accept ? 'b0 : wr_beats_written + (beat_bits + 1)'(wdf_fire);
        wr_cmds_issued_next   = aw_accept ? 'b0 : wr_cmds_issued + (beat_bits + 1)'(wr_cmd_fire);

        wr_busy_next          = wr_busy;
        if (aw_accept) wr_busy_next = 1'b1;
        else if (wr_cmd_fire && wr_cmds_issued == (beat_bits + 1)'(beats_per_line - 1))
            wr_busy_next = 1'b0;

        wr_bvalid_next = wr_bvalid && !dbus.bready;
        if (wr_cmd_fire && wr_cmds_issued == (beat_bits + 1)'(beats_per_line - 1))
            wr_bvalid_next = 1'b1;
    end

    // The instruction port never writes
    assign ibus.awready = 1'b0;
    assign ibus.wready  = 1'b0;
    assign ibus.bvalid  = 1'b0;

    RXVDFF #(
        .width(line_addr_bits)
    ) wr_line_dff (
        .clk  (clk),
        .reset(reset),
        .en   (aw_accept),
        .d    (dbus.waddr[app_addr_width-1:line_bits]),
        .q    (wr_line)
    );

    RXVDFF wr_busy_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_busy_next),
        .q    (wr_busy)
    );

    RXVDFF wr_words_done_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_words_done_next),
        .q    (wr_words_done)
    );

    RXVDFF #(
        .width(2)
    ) wr_word_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_word_next),
        .q    (wr_word)
    );

    RXVDFF wr_beat_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_beat_valid_next),
        .q    (wr_beat_valid)
    );

    RXVDFF #(
        .width(128)
    ) wr_beat_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_beat_data_next),
        .q    (wr_beat_data)
    );

    RXVDFF #(
        .width    (16),
        .reset_val(16'hffff)
    ) wr_beat_mask_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_beat_mask_next),
        .q    (wr_beat_mask)
    );

    RXVDFF #(
        .width(beat_bits + 1)
    ) wr_beats_written_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_beats_written_next),
        .q    (wr_beats_written)
    );

    RXVDFF #(
        .width(beat_bits + 1)
    ) wr_cmds_issued_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_cmds_issued_next),
        .q    (wr_cmds_issued)
    );

    RXVDFF wr_bvalid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wr_bvalid_next),
        .q    (wr_bvalid)
    );

    RXVDFF rd_issue_active_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_issue_active_next),
        .q    (rd_issue_active)
    );

    RXVDFF #(
        .width(beat_bits)
    ) rd_issue_beat_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_issue_beat_next),
        .q    (rd_issue_beat)
    );

    RXVDFF #(
        .width(line_addr_bits)
    ) rd_issue_line_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_issue_line_next),
        .q    (rd_issue_line)
    );

    RXVDFF rd_last_port_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_last_port_next),
        .q    (rd_last_port)
    );

    RXVDFF #(
        .width(rd_fifo_order + 1)
    ) rd_credits_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (rd_credits_next),
        .q    (rd_credits)
    );

    // Only whole lines are supported
    RXVAssert #(
        .message("MIGFrontend: read is not a full line")
    ) rd_full_line (
        .clk      (clk),
        .en       (ar_accept),
        .condition(grant_d ? dbus.rlen == bus_len : ibus.rlen == bus_len)
    );

    RXVAssert #(
        .message("MIGFrontend: write is not a full line")
    ) wr_full_line (
        .clk      (clk),
        .en       (aw_accept),
        .condition(dbus.wlen == bus_len)
    );

    RXVAssert #(
        .message("MIGFrontend: write on instruction port")
    ) no_ibus_write (
        .clk      (clk),
        .en       (!reset),
        .condition(!ibus.awvalid && !ibus.wvalid)
    );

    RXVAssert #(
        .message("MIGFrontend: read data FIFO overflow")
    ) rd_fifo_no_overflow (
        .clk      (clk),
        .en       (app_rd_data_valid && !reset),
        .condition(rd_fifo_wr_ptr != {~rd_fifo_rd_ptr[rd_fifo_order], rd_fifo_rd_ptr[rd_fifo_order-1:0]})
    );

endmodule
