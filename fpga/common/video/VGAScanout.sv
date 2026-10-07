// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// 640x480@60 RGB565 framebuffer scanout from SDRAM through the video port
// of SDRAMFrontend, to a 4-bit per channel resistor DAC.
//
// The framebuffer is fixed at fb_base with a stride of 1280 bytes, as
// described to Linux with simple-framebuffer, so there are no registers.
// Two scanline buffers are used ping-pong: when the active part of line y
// ends its buffer is free, so line y + 2 is fetched into it while line y + 1
// is displayed from the other, giving the fetch a line and the horizontal
// blanking.  The request for each line
// is handed from the pixel clock domain with a toggle and the line number,
// which is stable for a whole line, so the fetch can't drift out of step
// with the display.  Pixel 2n is in the low half of word n.
module VGAScanout #(
    parameter logic [31:0] fb_base = 32'h83f00000
) (
    // System clock domain
    input  logic                   clk,
    input  logic                   reset,
           MemInterface.Manager    vbus,
    // Pixel clock domain, 25MHz
    input  logic                   vga_clk,
    input  logic                   vga_reset,
    output logic             [3:0] vga_r,
    output logic             [3:0] vga_g,
    output logic             [3:0] vga_b,
    output logic                   vga_hsync,
    output logic                   vga_vsync
);

    localparam int h_active = 640;
    localparam int h_front = 16;
    localparam int h_sync = 96;
    localparam int h_back = 48;
    localparam int h_total = h_active + h_front + h_sync + h_back;
    localparam int v_active = 480;
    localparam int v_front = 10;
    localparam int v_sync = 2;
    localparam int v_back = 33;
    localparam int v_total = v_active + v_front + v_sync + v_back;

    localparam int words_per_line = h_active / 2;
    localparam int bursts_per_line = words_per_line / 16;
    localparam int stride = h_active * 2;

    // ------------------------------------------------------------------
    // Pixel clock domain: timing, line requests and pixel output.  Active
    // video is h < h_active, v < v_active, followed by the porches and
    // sync.
    // ------------------------------------------------------------------
    logic [ 9:0] hcount;
    logic [ 9:0] vcount;
    logic [ 8:0] req_line;
    logic        req_toggle;
    logic [ 9:0] fetch_line;
    // The DAC only takes the top 4 bits of each component.
    // verilator lint_off UNUSEDSIGNAL
    logic [31:0] rd_word;
    // verilator lint_on UNUSEDSIGNAL
    logic        active_q;
    logic        hsync_q;
    logic        vsync_q;
    logic        odd_q;

    always_comb fetch_line = vcount >= 10'(v_total - 2) ? vcount + 10'd2 - 10'(v_total) : vcount + 10'd2;

    always_ff @(posedge vga_clk) begin
        hcount <= hcount == 10'(h_total - 1) ? 10'd0 : hcount + 1'b1;
        if (hcount == 10'(h_total - 1)) vcount <= vcount == 10'(v_total - 1) ? 10'd0 : vcount + 1'b1;

        if (hcount == 10'(h_active - 1) && fetch_line < 10'(v_active)) begin
            req_line   <= fetch_line[8:0];
            req_toggle <= ~req_toggle;
        end

        // Matches the line buffer read latency.
        active_q  <= hcount < 10'(h_active) && vcount < 10'(v_active);
        hsync_q   <= !(hcount >= 10'(h_active + h_front) && hcount < 10'(h_active + h_front + h_sync));
        vsync_q   <= !(vcount >= 10'(v_active + v_front) && vcount < 10'(v_active + v_front + v_sync));
        odd_q     <= hcount[0];

        vga_hsync <= hsync_q;
        vga_vsync <= vsync_q;
        if (active_q) begin
            vga_r <= odd_q ? rd_word[31:28] : rd_word[15:12];
            vga_g <= odd_q ? rd_word[26:23] : rd_word[10:7];
            vga_b <= odd_q ? rd_word[20:17] : rd_word[4:1];
        end else begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end

        if (vga_reset) begin
            hcount     <= '0;
            vcount     <= 10'(v_total - 1);
            req_toggle <= 1'b0;
            req_line   <= '0;
            active_q   <= 1'b0;
            vga_r      <= 4'h0;
            vga_g      <= 4'h0;
            vga_b      <= 4'h0;
            vga_hsync  <= 1'b1;
            vga_vsync  <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Line buffers: written in the system clock domain, read in the pixel
    // clock domain.
    // ------------------------------------------------------------------
    logic [31:0] line_buf[2 * words_per_line];
    logic [ 9:0] buf_waddr;
    logic        buf_wr;
    logic [31:0] buf_wdata;

    always_ff @(posedge clk) begin
        if (buf_wr) line_buf[buf_waddr] <= buf_wdata;
    end

    always_ff @(posedge vga_clk) begin
        // Line y is displayed from the half that line y was fetched into.
        rd_word <= line_buf[(vcount[0] ? 10'(words_per_line) : 10'd0) +
                            (hcount < 10'(h_active) ? 10'(hcount[9:1]) : 10'd0)];
    end

    // ------------------------------------------------------------------
    // System clock domain: fetch the requested line.
    // ------------------------------------------------------------------
    logic        req_sync;
    logic        req_seen;
    logic        fetching;
    logic [ 8:0] line;
    logic [ 4:0] burst;
    logic        ar_pending;
    logic [ 8:0] word;

    BitSync req_bitsync (
        .clk  (clk),
        .reset(reset),
        .d    (req_toggle),
        .q    (req_sync)
    );

    assign vbus.raddr   = fb_base + 32'(line) * 32'(stride) + 32'(burst) * 32'd64;
    assign vbus.rlen    = 4'd15;
    assign vbus.arvalid = ar_pending;
    assign vbus.rready  = 1'b1;
    assign vbus.waddr   = '0;
    assign vbus.wlen    = '0;
    assign vbus.awvalid = 1'b0;
    assign vbus.wvalid  = 1'b0;
    assign vbus.wdata   = '0;
    assign vbus.wstb    = '0;
    assign vbus.wlast   = 1'b0;
    assign vbus.bready  = 1'b1;

    assign buf_wr       = vbus.rvalid;
    assign buf_wdata    = vbus.rdata;
    // Words per line isn't a power of two so the halves are 320 apart.
    assign buf_waddr    = (line[0] ? 10'(words_per_line) : 10'd0) + 10'(word);

    always_ff @(posedge clk) begin
        if (req_sync != req_seen && !fetching) begin
            req_seen   <= req_sync;
            // The line number has been stable for a whole line.
            line       <= req_line;
            burst      <= '0;
            word       <= '0;
            fetching   <= 1'b1;
            ar_pending <= 1'b1;
        end

        if (vbus.arvalid && vbus.arready) ar_pending <= 1'b0;

        if (vbus.rvalid) begin
            word <= word + 1'b1;
            if (vbus.rlast) begin
                if (burst == 5'(bursts_per_line - 1)) begin
                    fetching <= 1'b0;
                end else begin
                    burst      <= burst + 1'b1;
                    ar_pending <= 1'b1;
                end
            end
        end

        if (reset) begin
            req_seen   <= 1'b0;
            fetching   <= 1'b0;
            ar_pending <= 1'b0;
        end
    end

endmodule
