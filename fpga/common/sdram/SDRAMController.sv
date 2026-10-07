// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// SDR SDRAM controller for x16 parts, e.g. the IS42S16320D on the DE0-CV.
//
// The mode register is programmed for a burst length of 1 and a column
// command is issued every cycle, so a request is any number of 32-bit words
// within a row (a cache line or a single word) and DQM masks every 16-bit
// beat individually.  Rows are closed after every request (precharge on
// completion) so refresh can be issued from idle without a precharge.
//
// Requests are word addresses within the device.  Write data must all be
// available from the write data port when a write is requested, it is
// consumed one word every two cycles with no stalls.  Read data is returned
// at the same rate with no backpressure, the requester must have space for
// the whole request.
//
// All outputs are registered so they can be packed into the I/O cells, read
// data is captured into a register at read_latency edges after the edge that
// registers the READ command: CL + 1 with a zero delay model and the clock
// to the SDRAM in phase, the board picks the value that meets timing for its
// clock phase.
module SDRAMController #(
    parameter int clk_period_ps       = 16667,
    parameter int cas_latency         = 2,
    parameter int read_latency        = cas_latency + 1,
    parameter int row_bits            = 13,
    parameter int col_bits            = 10,
    parameter int bank_bits           = 2,
    parameter int init_wait_ns        = 200000,
    parameter int init_refreshes      = 8,
    parameter int refresh_interval_ns = 7800,
    parameter int trcd_ns             = 15,
    parameter int trp_ns              = 15,
    parameter int trc_ns              = 66,
    parameter int tras_ns             = 42,
    parameter int trfc_ns             = 66,
    parameter int twr_ns              = 15,
    parameter int tmrd_cycles         = 2
) (
    input  logic                     clk,
    input  logic                     reset,
    output logic                     init_done,
    // Request
    input  logic                     req_valid,
    output logic                     req_ready,
    input  logic                     req_write,
    input  logic [addr_bits-1:2]     req_addr,
    input  logic [              3:0] req_len,
    // Write data, one word per two cycles while writing
    input  logic [             31:0] wr_data,
    input  logic [              3:0] wr_strb,
    output logic                     wr_pop,
    // Read data
    output logic                     rd_valid,
    output logic [             31:0] rd_data,
    output logic                     rd_last,
    // SDRAM pins
    output logic                     s_cke,
    output logic                     s_cs_n,
    output logic                     s_ras_n,
    output logic                     s_cas_n,
    output logic                     s_we_n,
    output logic [    bank_bits-1:0] s_ba,
    output logic [     row_bits-1:0] s_addr,
    output logic [              1:0] s_dqm,
    output logic [             15:0] s_dq_o,
    output logic                     s_dq_oe,
    input  logic [             15:0] s_dq_i
);

    localparam int addr_bits = row_bits + col_bits + bank_bits + 1;

    function automatic int ns_to_cycles(input int ns);
        ns_to_cycles = (ns * 1000 + clk_period_ps - 1) / clk_period_ps;
    endfunction

    function automatic int at_least_one(input int n);
        at_least_one = n < 1 ? 1 : n;
    endfunction

    localparam int init_wait_cycles = ns_to_cycles(init_wait_ns);
    localparam int refresh_cycles = ns_to_cycles(refresh_interval_ns) - 1;
    localparam int trcd = at_least_one(ns_to_cycles(trcd_ns));
    localparam int trp = at_least_one(ns_to_cycles(trp_ns));
    localparam int trc = at_least_one(ns_to_cycles(trc_ns));
    localparam int tras = at_least_one(ns_to_cycles(tras_ns));
    localparam int trfc = at_least_one(ns_to_cycles(trfc_ns));
    // Write recovery is counted from the cycle after the last write.
    localparam int twr = at_least_one(ns_to_cycles(twr_ns));

    localparam int timer_bits = $clog2(init_wait_cycles + 1);
    localparam int refresh_bits = $clog2(refresh_cycles + 1);

    initial assert (col_bits >= 6 && row_bits > 10);
    initial assert (cas_latency == 2 || cas_latency == 3);
    initial assert (read_latency >= cas_latency + 1);

    // Command truth table: CS RAS CAS WE
    localparam logic [3:0] CMD_NOP = 4'b0111;
    localparam logic [3:0] CMD_ACT = 4'b0011;
    localparam logic [3:0] CMD_READ = 4'b0101;
    localparam logic [3:0] CMD_WRITE = 4'b0100;
    localparam logic [3:0] CMD_PRE = 4'b0010;
    localparam logic [3:0] CMD_REF = 4'b0001;
    localparam logic [3:0] CMD_MRS = 4'b0000;

    typedef enum logic [2:0] {
        STATE_INIT_WAIT,
        STATE_INIT_PRE,
        STATE_INIT_REF,
        STATE_INIT_MRS,
        STATE_IDLE,
        STATE_ACT,
        STATE_RW,
        STATE_PRE
    } state_t;

    state_t                    state;
    logic   [  timer_bits-1:0] timer;
    logic   [             3:0] init_refs;
    // ACT/REF to the next ACT/REF
    logic   [  timer_bits-1:0] rc_timer;
    // ACT to PRE
    logic   [  timer_bits-1:0] ras_timer;
    logic   [refresh_bits-1:0] refresh_timer;
    logic                      refresh_pending;

    // Latched request
    logic                      write;
    logic   [   bank_bits-1:0] bank;
    logic   [    col_bits-1:0] col;
    logic   [             4:0] beats_left;
    logic                      high_half;

    // Read capture
    logic   [  read_latency:0] rd_pipe;
    logic   [  read_latency:0] rd_pipe_last;
    (* altera_attribute = "-name FAST_INPUT_REGISTER ON" *)
    logic   [            15:0] dq_i_q;
    logic   [            15:0] rd_lo;
    logic                      rd_lo_valid;

    // Registered pin values
    logic   [             3:0] cmd;

    logic                      issue_rw;
    logic                      issue_last;

    assign {s_cs_n, s_ras_n, s_cas_n, s_we_n} = cmd;

    // Power up as NOP: the controller is only reset after configuration
    // and all zeros is LOAD MODE REGISTER.
    initial begin
        cmd     = CMD_NOP;
        s_dq_oe = 1'b0;
    end

    always_comb begin
        req_ready  = state == STATE_IDLE && !refresh_pending && rc_timer == '0 && timer == '0 &&
            init_done;
        issue_rw   = state == STATE_RW;
        issue_last = issue_rw && beats_left == 5'd0;
        // The high half of each word pops it from the write data port.
        wr_pop     = issue_rw && write && high_half;
    end

    always_ff @(posedge clk) begin
        cmd     <= CMD_NOP;
        s_dq_oe <= 1'b0;
        s_dqm   <= 2'b00;

        if (timer != '0) timer <= timer - 1'b1;
        if (rc_timer != '0) rc_timer <= rc_timer - 1'b1;
        if (ras_timer != '0) ras_timer <= ras_timer - 1'b1;

        if (refresh_timer == '0) begin
            refresh_timer   <= refresh_bits'(refresh_cycles);
            refresh_pending <= 1'b1;
        end else begin
            refresh_timer <= refresh_timer - 1'b1;
        end

        unique case (state)
            STATE_INIT_WAIT: begin
                if (timer == '0) begin
                    cmd        <= CMD_PRE;
                    s_addr[10] <= 1'b1;
                    timer      <= timer_bits'(trp - 1);
                    state      <= STATE_INIT_PRE;
                end
            end
            STATE_INIT_PRE: begin
                if (timer == '0) begin
                    cmd   <= CMD_REF;
                    timer <= timer_bits'(trfc - 1);
                    state <= STATE_INIT_REF;
                end
            end
            STATE_INIT_REF: begin
                if (timer == '0) begin
                    if (init_refs == 4'(init_refreshes - 1)) begin
                        cmd    <= CMD_MRS;
                        s_ba   <= '0;
                        // Burst length 1, sequential, CAS latency,
                        // programmed burst length for writes.
                        s_addr <= row_bits'({3'(cas_latency), 4'b0000});
                        timer  <= timer_bits'(tmrd_cycles - 1);
                        state  <= STATE_INIT_MRS;
                    end else begin
                        cmd       <= CMD_REF;
                        init_refs <= init_refs + 1'b1;
                        timer     <= timer_bits'(trfc - 1);
                    end
                end
            end
            STATE_INIT_MRS: begin
                if (timer == '0) begin
                    init_done       <= 1'b1;
                    // The init refreshes count, start the interval now.
                    refresh_pending <= 1'b0;
                    refresh_timer   <= refresh_bits'(refresh_cycles);
                    state           <= STATE_IDLE;
                end
            end
            STATE_IDLE: begin
                if (refresh_pending && rc_timer == '0 && timer == '0) begin
                    cmd             <= CMD_REF;
                    rc_timer        <= timer_bits'(trfc - 1);
                    refresh_pending <= refresh_timer == '0;
                end else if (req_valid && req_ready) begin
                    cmd        <= CMD_ACT;
                    s_ba       <= req_addr[col_bits+1+:bank_bits];
                    s_addr     <= req_addr[col_bits+bank_bits+1+:row_bits];
                    write      <= req_write;
                    bank       <= req_addr[col_bits+1+:bank_bits];
                    col        <= {req_addr[col_bits:2], 1'b0};
                    beats_left <= {req_len, 1'b1};
                    high_half  <= 1'b0;
                    rc_timer   <= timer_bits'(trc - 1);
                    ras_timer  <= timer_bits'(tras - 1);
                    // The first column command is registered on leaving
                    // STATE_ACT, tRCD after the ACT.
                    timer      <= timer_bits'(trcd < 2 ? 0 : trcd - 2);
                    state      <= trcd < 2 ? STATE_RW : STATE_ACT;
                end
            end
            STATE_ACT: begin
                if (timer == '0) state <= STATE_RW;
            end
            STATE_RW: begin
                cmd        <= write ? CMD_WRITE : CMD_READ;
                s_ba       <= bank;
                // A10 low: no auto precharge
                s_addr     <= row_bits'(col);
                s_dq_oe    <= write;
                s_dq_o     <= high_half ? wr_data[31:16] : wr_data[15:0];
                s_dqm      <= write ? ~(high_half ? wr_strb[3:2] : wr_strb[1:0]) : 2'b00;
                col        <= col + 1'b1;
                high_half  <= ~high_half;
                beats_left <= beats_left - 1'b1;
                if (beats_left == 5'd0) begin
                    // A read can be precharged straight away, a write
                    // needs the write recovery time from the last beat.
                    timer <= write ? timer_bits'(twr) : '0;
                    state <= STATE_PRE;
                end
            end
            STATE_PRE: begin
                if (timer == '0 && ras_timer == '0) begin
                    cmd        <= CMD_PRE;
                    s_ba       <= bank;
                    s_addr[10] <= 1'b0;
                    timer      <= timer_bits'(trp - 1);
                    state      <= STATE_IDLE;
                end
            end
            default: ;
        endcase

        if (reset) begin
            state           <= STATE_INIT_WAIT;
            cmd             <= CMD_NOP;
            s_dq_oe         <= 1'b0;
            timer           <= timer_bits'(init_wait_cycles);
            rc_timer        <= '0;
            ras_timer       <= '0;
            refresh_timer   <= refresh_bits'(refresh_cycles);
            refresh_pending <= 1'b0;
            init_refs       <= '0;
            init_done       <= 1'b0;
        end
    end

    assign s_cke = 1'b1;

    // Read data: the pipeline tracks each READ beat to the edge that
    // captures it, words are assembled from pairs of beats, low half first.
    always_ff @(posedge clk) begin
        dq_i_q       <= s_dq_i;
        rd_pipe      <= {rd_pipe[read_latency-1:0], issue_rw && !write};
        rd_pipe_last <= {rd_pipe_last[read_latency-1:0], issue_last && !write};
        rd_valid     <= 1'b0;
        rd_last      <= 1'b0;

        if (rd_pipe[read_latency]) begin
            if (rd_lo_valid) begin
                rd_valid    <= 1'b1;
                rd_data     <= {dq_i_q, rd_lo};
                rd_last     <= rd_pipe_last[read_latency];
                rd_lo_valid <= 1'b0;
            end else begin
                rd_lo       <= dq_i_q;
                rd_lo_valid <= 1'b1;
            end
        end

        if (reset) begin
            rd_pipe      <= '0;
            rd_pipe_last <= '0;
            rd_valid     <= 1'b0;
            rd_lo_valid  <= 1'b0;
        end
    end

endmodule
