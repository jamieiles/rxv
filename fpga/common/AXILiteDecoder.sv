// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// Device bus: single word accesses from a MemInterface manager, decoded by
// address to one of num_slaves AXI4-Lite subordinates.  Only one
// transaction is ever in flight, as with BusAdapter.
//
// AW and W are presented together and RREADY is held while a read is
// outstanding with the response buffered here, as RXVCLINT relies on both.
// Accesses that don't match any subordinate complete with zero read data.
module AXILiteDecoder #(
    parameter int                         num_slaves = 1,
    parameter logic [num_slaves*32-1:0] slave_base = '0,
    parameter logic [num_slaves*32-1:0] slave_mask = '0
) (
    input  logic                         clk,
    input  logic                         reset,
           MemInterface.Subordinate      bus,
    output logic        [          31:0] m_awaddr,
    output logic        [num_slaves-1:0] m_awvalid,
    input  logic        [num_slaves-1:0] m_awready,
    output logic        [          31:0] m_wdata,
    output logic        [           3:0] m_wstrb,
    output logic        [num_slaves-1:0] m_wvalid,
    input  logic        [num_slaves-1:0] m_wready,
    input  logic        [num_slaves-1:0] m_bvalid,
    output logic        [num_slaves-1:0] m_bready,
    output logic        [          31:0] m_araddr,
    output logic        [num_slaves-1:0] m_arvalid,
    input  logic        [num_slaves-1:0] m_arready,
    input  logic        [num_slaves*32-1:0] m_rdata,
    input  logic        [num_slaves-1:0] m_rvalid,
    output logic        [num_slaves-1:0] m_rready
);

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_AR,
        STATE_R,
        STATE_RESP_R,
        STATE_W,
        STATE_AXI_W,
        STATE_B,
        STATE_RESP_B
    } state_t;

    state_t                  state;
    logic   [num_slaves-1:0] sel;
    logic   [num_slaves-1:0] decode_r;
    logic   [num_slaves-1:0] decode_w;
    logic   [          31:0] addr;
    logic   [          31:0] rdata;
    logic                    aw_done;
    logic                    w_done;
    logic   [          31:0] sel_rdata;

    always_comb begin
        for (int i = 0; i < num_slaves; ++i) begin
            decode_r[i] = (bus.raddr & slave_mask[i*32+:32]) == slave_base[i*32+:32];
            decode_w[i] = (bus.waddr & slave_mask[i*32+:32]) == slave_base[i*32+:32];
        end

        sel_rdata = '0;
        for (int i = 0; i < num_slaves; ++i) if (sel[i]) sel_rdata = m_rdata[i*32+:32];
    end

    assign bus.arready = state == STATE_IDLE;
    assign bus.awready = state == STATE_IDLE && !bus.arvalid;
    assign bus.wready  = state == STATE_W;
    assign bus.rvalid  = state == STATE_RESP_R;
    assign bus.rdata   = rdata;
    assign bus.rlast   = 1'b1;
    assign bus.bvalid  = state == STATE_RESP_B;

    assign m_araddr    = addr;
    assign m_awaddr    = addr;
    assign m_arvalid   = state == STATE_AR ? sel : '0;
    assign m_rready    = state == STATE_AR || state == STATE_R ? sel : '0;
    assign m_awvalid   = state == STATE_AXI_W && !aw_done ? sel : '0;
    assign m_wvalid    = state == STATE_AXI_W && !w_done ? sel : '0;
    assign m_bready    = state == STATE_AXI_W || state == STATE_B ? sel : '0;

    always_ff @(posedge clk) begin
        unique case (state)
            STATE_IDLE: begin
                if (bus.arvalid) begin
                    addr  <= bus.raddr;
                    sel   <= decode_r;
                    rdata <= '0;
                    state <= |decode_r ? STATE_AR : STATE_RESP_R;
                end else if (bus.awvalid) begin
                    addr    <= bus.waddr;
                    sel     <= decode_w;
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    state   <= STATE_W;
                end
            end
            STATE_AR: begin
                if (|(m_arready & sel)) state <= STATE_R;
                if (|(m_rvalid & sel)) begin
                    rdata <= sel_rdata;
                    state <= STATE_RESP_R;
                end
            end
            STATE_R: begin
                if (|(m_rvalid & sel)) begin
                    rdata <= sel_rdata;
                    state <= STATE_RESP_R;
                end
            end
            STATE_RESP_R: begin
                if (bus.rready) state <= STATE_IDLE;
            end
            STATE_W: begin
                if (bus.wvalid) begin
                    m_wdata <= bus.wdata;
                    m_wstrb <= bus.wstb;
                    state   <= |sel ? STATE_AXI_W : STATE_RESP_B;
                end
            end
            STATE_AXI_W: begin
                if (|(m_awready & sel)) aw_done <= 1'b1;
                if (|(m_wready & sel)) w_done <= 1'b1;
                if ((aw_done || |(m_awready & sel)) && (w_done || |(m_wready & sel)))
                    state <= STATE_B;
                if (|(m_bvalid & sel)) state <= STATE_RESP_B;
            end
            STATE_B: begin
                if (|(m_bvalid & sel)) state <= STATE_RESP_B;
            end
            STATE_RESP_B: begin
                if (bus.bready) state <= STATE_IDLE;
            end
            default: state <= STATE_IDLE;
        endcase

        if (reset) state <= STATE_IDLE;
    end

endmodule
