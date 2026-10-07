// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

`define PORT_SIGNALS(p) \
    input  logic         p``_valid, \
    input  logic [ 31:2] p``_address, \
    input  logic [  3:0] p``_len, \
    input  logic         p``_wren, \
    input  logic [ 31:0] p``_wdata, \
    input  logic [  3:0] p``_bytesel, \
    output logic         p``_complete, \
    output logic [ 31:0] p``_rdata, \
    output logic         p``_beat_ack, \
    output logic [  3:0] p``_beat_num,

`define PORT_ADAPTER(p) \
    BusAdapter p``_adapter ( \
        .clk          (clk), \
        .reset        (reset), \
        .bus          (p``_bus.Manager), \
        .valid        (p``_valid), \
        .complete     (p``_complete), \
        .address      (p``_address), \
        .wdata        (p``_wdata), \
        .wren         (p``_wren), \
        .bytesel      (p``_bytesel), \
        .rdata        (p``_rdata), \
        .len          (p``_len), \
        .beat_num     (p``_beat_num), \
        .beat_num_next(p``_beat_num_next), \
        .beat_ack     (p``_beat_ack) \
    );

module SDRAMFrontendWrapper (
    input  logic         clk,
    input  logic         reset,
    `PORT_SIGNALS(i)
    `PORT_SIGNALS(d)
    `PORT_SIGNALS(x)
    `PORT_SIGNALS(v)
    `PORT_SIGNALS(u)
    output logic         init_done,
    // Write responses: u, v, x, d, i
    output logic [  4:0] bvalid,
    // SDRAM pins
    output logic         s_cke,
    output logic         s_cs_n,
    output logic         s_ras_n,
    output logic         s_cas_n,
    output logic         s_we_n,
    output logic [  1:0] s_ba,
    output logic [ 12:0] s_addr,
    output logic [  1:0] s_dqm,
    output logic [ 15:0] s_dq_o,
    output logic         s_dq_oe,
    input  logic [ 15:0] s_dq_i
);

    MemInterface i_bus ();
    MemInterface d_bus ();
    MemInterface x_bus ();
    MemInterface v_bus ();
    MemInterface u_bus ();

    // verilator lint_off UNUSED
    logic [ 3:0] i_beat_num_next;
    logic [ 3:0] d_beat_num_next;
    logic [ 3:0] x_beat_num_next;
    logic [ 3:0] v_beat_num_next;
    logic [ 3:0] u_beat_num_next;
    logic        rd_last;
    // verilator lint_on UNUSED

    `PORT_ADAPTER(i)
    `PORT_ADAPTER(d)
    `PORT_ADAPTER(x)
    `PORT_ADAPTER(v)
    `PORT_ADAPTER(u)

    assign bvalid = {u_bus.bvalid, v_bus.bvalid, x_bus.bvalid, d_bus.bvalid, i_bus.bvalid};

    logic        req_valid;
    logic        req_ready;
    logic        req_write;
    logic [25:2] req_addr;
    logic [ 3:0] req_len;
    logic [31:0] wr_data;
    logic [ 3:0] wr_strb;
    logic        wr_pop;
    logic        rd_valid;
    logic [31:0] rd_data;

    SDRAMFrontend frontend (
        .clk      (clk),
        .reset    (reset),
        .ibus     (i_bus.Subordinate),
        .dbus     (d_bus.Subordinate),
        .xbus     (x_bus.Subordinate),
        .vbus     (v_bus.Subordinate),
        .ubus     (u_bus.Subordinate),
        .init_done(init_done),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr (req_addr),
        .req_len  (req_len),
        .wr_data  (wr_data),
        .wr_strb  (wr_strb),
        .wr_pop   (wr_pop),
        .rd_valid (rd_valid),
        .rd_data  (rd_data),
        .rd_last  (rd_last)
    );

    // 60MHz with a short power up wait to keep the simulation quick.
    SDRAMController #(
        .clk_period_ps(16667),
        .init_wait_ns (2000)
    ) controller (
        .clk      (clk),
        .reset    (reset),
        .init_done(init_done),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr (req_addr),
        .req_len  (req_len),
        .wr_data  (wr_data),
        .wr_strb  (wr_strb),
        .wr_pop   (wr_pop),
        .rd_valid (rd_valid),
        .rd_data  (rd_data),
        .rd_last  (rd_last),
        .s_cke    (s_cke),
        .s_cs_n   (s_cs_n),
        .s_ras_n  (s_ras_n),
        .s_cas_n  (s_cas_n),
        .s_we_n   (s_we_n),
        .s_ba     (s_ba),
        .s_addr   (s_addr),
        .s_dqm    (s_dqm),
        .s_dq_o   (s_dq_o),
        .s_dq_oe  (s_dq_oe),
        .s_dq_i   (s_dq_i)
    );

endmodule
