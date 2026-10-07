// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// VGAScanout with the video port brought out for a memory model and the
// pixel clock at half the system clock.
module VGAScanoutWrapper (
    input  logic        clk,
    input  logic        reset,
    output logic [31:0] v_raddr,
    output logic [ 3:0] v_rlen,
    output logic        v_arvalid,
    input  logic        v_arready,
    input  logic        v_rvalid,
    input  logic [31:0] v_rdata,
    input  logic        v_rlast,
    output logic        v_rready,
    // Write channel inputs to the read only manager, unused
    output logic [ 2:0] v_write_resp,
    output logic        vga_clk,
    output logic [ 3:0] vga_r,
    output logic [ 3:0] vga_g,
    output logic [ 3:0] vga_b,
    output logic        vga_hsync,
    output logic        vga_vsync
);

    MemInterface vbus ();

    // verilator lint_off UNUSEDSIGNAL
    logic [31:0] v_waddr;
    logic [ 3:0] v_wlen;
    logic        v_awvalid;
    logic        v_wvalid;
    logic [31:0] v_wdata;
    logic [ 3:0] v_wstb;
    logic        v_wlast;
    logic        v_bready;
    // verilator lint_on UNUSEDSIGNAL

    assign v_raddr       = vbus.raddr;
    assign v_rlen        = vbus.rlen;
    assign v_arvalid     = vbus.arvalid;
    assign v_rready      = vbus.rready;
    assign v_waddr       = vbus.waddr;
    assign v_wlen        = vbus.wlen;
    assign v_awvalid     = vbus.awvalid;
    assign v_wvalid      = vbus.wvalid;
    assign v_wdata       = vbus.wdata;
    assign v_wstb        = vbus.wstb;
    assign v_wlast       = vbus.wlast;
    assign v_bready      = vbus.bready;
    assign vbus.arready  = v_arready;
    assign vbus.rvalid   = v_rvalid;
    assign vbus.rdata    = v_rdata;
    assign vbus.rlast    = v_rlast;
    assign vbus.awready  = 1'b0;
    assign vbus.wready   = 1'b0;
    assign vbus.bvalid   = 1'b0;
    assign v_write_resp  = {vbus.awready, vbus.wready, vbus.bvalid};

    logic vga_reset;

    always_ff @(posedge clk) begin
        vga_clk <= ~vga_clk;
        if (reset) vga_clk <= 1'b0;
    end

    always_ff @(posedge vga_clk) vga_reset <= reset;

    VGAScanout scanout (
        .clk      (clk),
        .reset    (reset),
        .vbus     (vbus.Manager),
        .vga_clk  (vga_clk),
        .vga_reset(vga_reset),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync)
    );

endmodule
