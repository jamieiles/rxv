// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// One port of BootROM: cache line bursts read from or written to the RAM,
// a word per cycle.
module BootROMPort #(
    parameter int addr_bits = 13
) (
    input  logic                           clk,
    input  logic                           reset,
           MemInterface.Subordinate        bus,
    output logic           [addr_bits-1:0] ram_addr,
    output logic                           ram_we,
    output logic           [          3:0] ram_be,
    output logic           [         31:0] ram_wdata,
    input  logic           [         31:0] ram_q
);

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_R,
        STATE_W,
        STATE_B
    } state_t;

    state_t                 state;
    logic   [addr_bits-1:0] cur;
    logic   [          3:0] remaining;
    logic                   r_fire;

    assign bus.arready = state == STATE_IDLE;
    assign bus.awready = state == STATE_IDLE && !bus.arvalid;
    assign bus.rvalid  = state == STATE_R;
    assign bus.rdata   = ram_q;
    assign bus.rlast   = remaining == 4'd0;
    assign bus.wready  = state == STATE_W;
    assign bus.bvalid  = state == STATE_B;

    always_comb begin
        r_fire    = state == STATE_R && bus.rready;

        ram_addr  = cur;
        if (state == STATE_IDLE && bus.arvalid) ram_addr = bus.raddr[addr_bits+1:2];
        else if (r_fire) ram_addr = cur + 1'b1;

        ram_we    = state == STATE_W && bus.wvalid;
        ram_be    = bus.wstb;
        ram_wdata = bus.wdata;
    end

    always_ff @(posedge clk) begin
        unique case (state)
            STATE_IDLE: begin
                if (bus.arvalid) begin
                    cur       <= bus.raddr[addr_bits+1:2];
                    remaining <= bus.rlen;
                    state     <= STATE_R;
                end else if (bus.awvalid) begin
                    cur   <= bus.waddr[addr_bits+1:2];
                    state <= STATE_W;
                end
            end
            STATE_R: begin
                if (bus.rready) begin
                    cur       <= cur + 1'b1;
                    remaining <= remaining - 1'b1;
                    if (remaining == 4'd0) state <= STATE_IDLE;
                end
            end
            STATE_W: begin
                if (bus.wvalid) begin
                    cur <= cur + 1'b1;
                    if (bus.wlast) state <= STATE_B;
                end
            end
            STATE_B: begin
                if (bus.bready) state <= STATE_IDLE;
            end
            default: state <= STATE_IDLE;
        endcase

        if (reset) state <= STATE_IDLE;
    end

endmodule
