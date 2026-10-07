// Copyright 2017, 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// PS/2 host, from s80x86.  The clock and data lines are open drain: the
// host only ever pulls them low and the board provides the pull-ups.
module PS2Host #(
    parameter int clk_freq = 60000000
) (
    input  logic       clk,
    input  logic       reset,
    // Host signals
    output logic [7:0] rx,
    output logic       rx_valid,
    output logic       error,
    input  logic       start_tx,
    input  logic [7:0] tx,
    output logic       tx_busy,
    output logic       tx_complete,
    // Connector signals
    input  logic       ps2_clk_i,
    output logic       ps2_clk_low,
    input  logic       ps2_dat_i,
    output logic       ps2_dat_low
);

    // Hold the clock low for 100us to request to send.
    localparam int tx_clock_inhibit_reload = (clk_freq / 1000000) * 100;
    localparam int tx_clock_inhibit_bits = $clog2(tx_clock_inhibit_reload + 1);

    typedef enum logic [3:0] {
        STATE_IDLE,
        // Receive
        STATE_RX,
        STATE_RX_PARITY,
        STATE_STOP,
        // Transmit
        STATE_INHIBIT,
        STATE_TX_START,
        STATE_TX,
        STATE_TX_PARITY,
        STATE_TX_STOP,
        STATE_TX_ACK
    } state_t;

    state_t                            state;
    state_t                            next_state;
    logic   [tx_clock_inhibit_bits-1:0] clk_inhibit_count;
    logic                              ps2_clk_sync;
    logic                              ps2_dat_sync;
    logic                              last_ps2_clk;
    logic   [                     2:0] bitpos;
    logic   [                     7:0] tx_reg;
    logic                              dat_o;
    logic                              drive_dat;
    logic                              do_sample;

    // The host samples on the falling edge.
    assign do_sample   = last_ps2_clk & ~ps2_clk_sync;

    assign rx_valid    = state == STATE_STOP && do_sample;
    assign tx_complete = state == STATE_TX_ACK && do_sample;

    // Request to send: hold the clock low, then pull data low (the start
    // bit) before releasing the clock.
    assign ps2_clk_low = state == STATE_INHIBIT || state == STATE_TX_START;
    assign ps2_dat_low = drive_dat && !dat_o;

    BitSync clk_sync (
        .clk  (clk),
        .reset(reset),
        .d    (ps2_clk_i),
        .q    (ps2_clk_sync)
    );

    BitSync dat_sync (
        .clk  (clk),
        .reset(reset),
        .d    (ps2_dat_i),
        .q    (ps2_dat_sync)
    );

    always_comb begin
        unique case (state)
            STATE_IDLE:      next_state = do_sample && !ps2_dat_sync ? STATE_RX : STATE_IDLE;
            STATE_RX:        next_state = do_sample && bitpos == 3'd7 ? STATE_RX_PARITY : STATE_RX;
            STATE_RX_PARITY: next_state = do_sample ? STATE_STOP : STATE_RX_PARITY;
            STATE_STOP:      next_state = do_sample ? STATE_IDLE : STATE_STOP;
            STATE_INHIBIT:   next_state = ~|clk_inhibit_count ? STATE_TX_START : STATE_INHIBIT;
            STATE_TX_START:  next_state = STATE_TX;
            STATE_TX:        next_state = do_sample && bitpos == 3'd7 ? STATE_TX_PARITY : STATE_TX;
            STATE_TX_PARITY: next_state = do_sample ? STATE_TX_STOP : STATE_TX_PARITY;
            STATE_TX_STOP:   next_state = do_sample ? STATE_TX_ACK : STATE_TX_STOP;
            STATE_TX_ACK:    next_state = do_sample ? STATE_IDLE : STATE_TX_ACK;
            default:         next_state = STATE_IDLE;
        endcase

        if (start_tx) next_state = STATE_INHIBIT;
    end

    always_comb begin
        unique case (state)
            STATE_TX_START, STATE_TX, STATE_TX_PARITY: drive_dat = 1'b1;
            default: drive_dat = 1'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        state        <= next_state;
        last_ps2_clk <= ps2_clk_sync;

        if (state == STATE_INHIBIT) dat_o <= 1'b0;
        else if (do_sample && state == STATE_TX) dat_o <= tx_reg[bitpos];
        else if (do_sample && state == STATE_TX_PARITY) dat_o <= ~^tx_reg;

        if (start_tx) tx_busy <= 1'b1;
        else if (state == STATE_IDLE) tx_busy <= 1'b0;

        if (state == STATE_INHIBIT) clk_inhibit_count <= clk_inhibit_count - 1'b1;
        else clk_inhibit_count <= tx_clock_inhibit_bits'(tx_clock_inhibit_reload);

        if (state == STATE_RX || state == STATE_TX) bitpos <= do_sample ? bitpos + 1'b1 : bitpos;
        else bitpos <= 3'b0;

        if (state == STATE_RX && do_sample) rx <= {ps2_dat_sync, rx[7:1]};

        if (state == STATE_IDLE) error <= 1'b0;
        else if (state == STATE_RX_PARITY && do_sample) error <= ~^{rx, ps2_dat_sync};

        if (start_tx) tx_reg <= tx;

        if (reset) begin
            state             <= STATE_IDLE;
            last_ps2_clk      <= 1'b0;
            tx_busy           <= 1'b0;
            error             <= 1'b0;
            dat_o             <= 1'b1;
            clk_inhibit_count <= tx_clock_inhibit_bits'(tx_clock_inhibit_reload);
        end
    end

endmodule
