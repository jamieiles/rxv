// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// The DE0-CV system without the clocking and I/O buffers so that it can be
// simulated: bidirectional pins are split into inputs, outputs and output
// enables (or open drain pull downs).
//
// Memory map:
//   0x40000000  boot ROM
//   0x80000000  SDRAM (cached)
//   0xf0000000  CLINT, syscon reset at 0xf000c000
//   0xf8000000  uncached window onto the top 1MB of SDRAM (framebuffer)
//   0xfc000000  PLIC
//   0xfff90000  LEDs and seven segment displays
//   0xfffa0000  PS/2 keyboard
//   0xfffb0000  PS/2 mouse
//   0xfffc0000  SD host controller
//   0xffff1000  console UART, read out over JTAG
module DE0CVSoC #(
    parameter int    clk_freq          = 60000000,
    parameter        bootrom_init       = "",
    // Simulation can shorten the SDRAM power up wait
    parameter int    sdram_init_wait_ns = 200000,
    parameter int    sdram_read_latency = 3
) (
    input  logic        clk,
    input  logic        reset,
    // Request from software to reset the system
    output logic        sys_reset_req,
    // ~10MHz reference for mtime
    input  logic        clint_refclk,
    // SDRAM
    output logic        s_cke,
    output logic        s_cs_n,
    output logic        s_ras_n,
    output logic        s_cas_n,
    output logic        s_we_n,
    output logic [ 1:0] s_ba,
    output logic [12:0] s_addr,
    output logic [ 1:0] s_dqm,
    output logic [15:0] s_dq_o,
    output logic        s_dq_oe,
    input  logic [15:0] s_dq_i,
    // SD card, the tristate controls are active low
    output logic        sd_clk,
    output logic        sd_cmd_o,
    output logic        sd_cmd_t,
    input  logic        sd_cmd_i,
    output logic [ 3:0] sd_dat_o,
    output logic [ 3:0] sd_dat_t,
    input  logic [ 3:0] sd_dat_i,
    output logic        sd_activity,
    // PS/2, open drain
    input  logic        kbd_clk_i,
    output logic        kbd_clk_low,
    input  logic        kbd_dat_i,
    output logic        kbd_dat_low,
    input  logic        mouse_clk_i,
    output logic        mouse_clk_low,
    input  logic        mouse_dat_i,
    output logic        mouse_dat_low,
    // VGA
    input  logic        vga_clk,
    input  logic        vga_reset,
    output logic [ 3:0] vga_r,
    output logic [ 3:0] vga_g,
    output logic [ 3:0] vga_b,
    output logic        vga_hsync,
    output logic        vga_vsync,
    // Debug
    output logic [ 9:0] leds,
    output logic [41:0] hex_n,
    // Console UART read out
    input  logic [ 9:0] console_read_addr,
    output logic [63:0] console_read_data,
    output logic [31:0] console_byte_count,
    // For a JTAG probe:
    //   [255:224] the PC of the last jump and link
    //   [223:192] mtval
    //   [191:160] mepc
    //   [159:128] mcause
    //   [127:96]  counts of data and instruction bus requests (16 bits each)
    //   [95:64]   the address of the last device bus access
    //   [63:32]   {27'b0, mouse, kbd, sdhci, mtime and PLIC S interrupts}
    //   [31:0]    {the PC in execute, the privilege level}
    output logic [255:0] debug_probe
);

    localparam int num_slaves = 7;
    localparam int SLAVE_CLINT = 0;
    localparam int SLAVE_PLIC = 1;
    localparam int SLAVE_DEBUG = 2;
    localparam int SLAVE_KBD = 3;
    localparam int SLAVE_MOUSE = 4;
    localparam int SLAVE_SDHCI = 5;
    localparam int SLAVE_CONSOLE = 6;

    localparam logic [num_slaves*32-1:0] slave_base = {
        32'hffff0000, 32'hfffc0000, 32'hfffb0000, 32'hfffa0000, 32'hfff90000, 32'hfc000000, 32'hf0000000
    };
    localparam logic [num_slaves*32-1:0] slave_mask = {
        32'hffff0000, 32'hffff0000, 32'hffff0000, 32'hffff0000, 32'hffff0000, 32'hffc00000, 32'hffff0000
    };

    // ------------------------------------------------------------------
    // Core and address decode
    // ------------------------------------------------------------------
    MemInterface i_mem_bus ();
    MemInterface d_mem_bus ();
    MemInterface i_dram_bus ();
    MemInterface d_dram_bus ();
    MemInterface i_rom_bus ();
    MemInterface d_other_bus ();
    MemInterface d_rom_bus ();
    MemInterface d_io_bus ();
    MemInterface u_bus ();
    MemInterface dev_bus ();
    MemInterface x_bus ();
    MemInterface v_bus ();

    logic [63:0] mtime;
    logic        mtime_irq;
    // verilator lint_off UNUSEDSIGNAL
    logic [ 1:0] plic_irq;
    // verilator lint_on UNUSEDSIGNAL
    logic [159:0] debug_state;

    RXVCore #(
        .icache_nr_ways        (8),
        .icache_nr_lines       (64),
        .icache_line_size_bytes(64),
        .dcache_line_size_bytes(64),
        .dcache_nr_ways        (8),
        .dcache_nr_lines       (64),
        .banked_register_file  (1),
        .reset_address         (32'h40000000),
        .num_itlb_entries      (16),
        .num_dtlb_entries      (16)
    ) core (
        .clk            (clk),
        .reset          (reset),
        .instruction_bus(i_mem_bus.Manager),
        .data_bus       (d_mem_bus.Manager),
        .mtime          (mtime),
        .mtime_irq      (mtime_irq),
        // The S-mode context of the PLIC, the M-mode one is unused.
        .ext_irq        (plic_irq[1]),
        .debug_state    (debug_state)
    );


    MemSplit #(
        .match_base(32'h80000000),
        .match_mask(32'hf0000000)
    ) i_split (
        .upstream(i_mem_bus.Subordinate),
        .match   (i_dram_bus.Manager),
        .other   (i_rom_bus.Manager)
    );

    MemSplit #(
        .match_base(32'h80000000),
        .match_mask(32'hf0000000)
    ) d_split (
        .upstream(d_mem_bus.Subordinate),
        .match   (d_dram_bus.Manager),
        .other   (d_other_bus.Manager)
    );

    MemSplit #(
        .match_base(32'h40000000),
        .match_mask(32'hf0000000)
    ) d_rom_split (
        .upstream(d_other_bus.Subordinate),
        .match   (d_rom_bus.Manager),
        .other   (d_io_bus.Manager)
    );

    MemSplit #(
        .match_base(32'hf8000000),
        .match_mask(32'hff000000)
    ) d_fb_split (
        .upstream(d_io_bus.Subordinate),
        .match   (u_bus.Manager),
        .other   (dev_bus.Manager)
    );

    BootROM #(
        .size_bytes(32768),
        .init_file (bootrom_init)
    ) bootrom (
        .clk  (clk),
        .reset(reset),
        .ibus (i_rom_bus.Subordinate),
        .dbus (d_rom_bus.Subordinate)
    );

    // ------------------------------------------------------------------
    // SDRAM
    // ------------------------------------------------------------------
    logic        sdram_init_done;
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
    logic        rd_last;

    SDRAMFrontend frontend (
        .clk      (clk),
        .reset    (reset),
        .ibus     (i_dram_bus.Subordinate),
        .dbus     (d_dram_bus.Subordinate),
        .xbus     (x_bus.Subordinate),
        .vbus     (v_bus.Subordinate),
        .ubus     (u_bus.Subordinate),
        .init_done(sdram_init_done),
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

    SDRAMController #(
        .clk_period_ps(1000000000 / (clk_freq / 1000)),
        .init_wait_ns (sdram_init_wait_ns),
        .read_latency (sdram_read_latency)
    ) sdram (
        .clk      (clk),
        .reset    (reset),
        .init_done(sdram_init_done),
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

    VGAScanout #(
        .fb_base(32'h83f00000)
    ) scanout (
        .clk      (clk),
        .reset    (reset),
        .vbus     (v_bus.Manager),
        .vga_clk  (vga_clk),
        .vga_reset(vga_reset),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync)
    );

    // ------------------------------------------------------------------
    // Device bus
    // ------------------------------------------------------------------
    // verilator lint_off UNUSEDSIGNAL
    logic [             31:0] m_awaddr;
    logic [   num_slaves-1:0] m_awvalid;
    logic [   num_slaves-1:0] m_awready;
    logic [             31:0] m_wdata;
    logic [              3:0] m_wstrb;
    logic [   num_slaves-1:0] m_wvalid;
    logic [   num_slaves-1:0] m_wready;
    logic [   num_slaves-1:0] m_bvalid;
    logic [   num_slaves-1:0] m_bready;
    logic [             31:0] m_araddr;
    // verilator lint_on UNUSEDSIGNAL
    logic [   num_slaves-1:0] m_arvalid;
    logic [   num_slaves-1:0] m_arready;
    logic [num_slaves*32-1:0] m_rdata;
    logic [   num_slaves-1:0] m_rvalid;
    logic [   num_slaves-1:0] m_rready;

    AXILiteDecoder #(
        .num_slaves(num_slaves),
        .slave_base(slave_base),
        .slave_mask(slave_mask)
    ) decoder (
        .clk      (clk),
        .reset    (reset),
        .bus      (dev_bus.Subordinate),
        .m_awaddr (m_awaddr),
        .m_awvalid(m_awvalid),
        .m_awready(m_awready),
        .m_wdata  (m_wdata),
        .m_wstrb  (m_wstrb),
        .m_wvalid (m_wvalid),
        .m_wready (m_wready),
        .m_bvalid (m_bvalid),
        .m_bready (m_bready),
        .m_araddr (m_araddr),
        .m_arvalid(m_arvalid),
        .m_arready(m_arready),
        .m_rdata  (m_rdata),
        .m_rvalid (m_rvalid),
        .m_rready (m_rready)
    );

    // verilator lint_off UNUSEDSIGNAL
    logic [1:0] clint_bresp;
    logic [1:0] clint_rresp;
    logic [1:0] sdhci_bresp;
    logic [1:0] sdhci_rresp;
    // verilator lint_on UNUSEDSIGNAL

    RXVCLINT clint (
        .refclk       (clint_refclk),
        .s_axi_aclk   (clk),
        .s_axi_aresetn(~reset),
        .s_axi_awaddr (m_awaddr[15:0]),
        .s_axi_awvalid(m_awvalid[SLAVE_CLINT]),
        .s_axi_awready(m_awready[SLAVE_CLINT]),
        .s_axi_wdata  (m_wdata),
        .s_axi_wstrb  (m_wstrb),
        .s_axi_wvalid (m_wvalid[SLAVE_CLINT]),
        .s_axi_wready (m_wready[SLAVE_CLINT]),
        .s_axi_bresp  (clint_bresp),
        .s_axi_bvalid (m_bvalid[SLAVE_CLINT]),
        .s_axi_bready (m_bready[SLAVE_CLINT]),
        .s_axi_araddr (m_araddr[15:0]),
        .s_axi_arvalid(m_arvalid[SLAVE_CLINT]),
        .s_axi_arready(m_arready[SLAVE_CLINT]),
        .s_axi_rdata  (m_rdata[SLAVE_CLINT*32+:32]),
        .s_axi_rresp  (clint_rresp),
        .s_axi_rvalid (m_rvalid[SLAVE_CLINT]),
        .s_axi_rready (m_rready[SLAVE_CLINT]),
        .mtime        (mtime),
        .mtime_irq    (mtime_irq),
        .sys_reset    (sys_reset_req)
    );

    // Register blocks
    logic        plic_wr;
    logic [21:0] plic_waddr;
    logic [31:0] plic_wdata;
    logic [ 3:0] plic_wstrb;
    logic        plic_rd;
    logic [21:0] plic_raddr;
    logic [31:0] plic_rdata;

    AXILiteRegs #(
        .addr_bits(22)
    ) plic_regs (
        .clk          (clk),
        .reset        (reset),
        .s_axi_awaddr (m_awaddr[21:0]),
        .s_axi_awvalid(m_awvalid[SLAVE_PLIC]),
        .s_axi_awready(m_awready[SLAVE_PLIC]),
        .s_axi_wdata  (m_wdata),
        .s_axi_wstrb  (m_wstrb),
        .s_axi_wvalid (m_wvalid[SLAVE_PLIC]),
        .s_axi_wready (m_wready[SLAVE_PLIC]),
        .s_axi_bvalid (m_bvalid[SLAVE_PLIC]),
        .s_axi_bready (m_bready[SLAVE_PLIC]),
        .s_axi_araddr (m_araddr[21:0]),
        .s_axi_arvalid(m_arvalid[SLAVE_PLIC]),
        .s_axi_arready(m_arready[SLAVE_PLIC]),
        .s_axi_rdata  (m_rdata[SLAVE_PLIC*32+:32]),
        .s_axi_rvalid (m_rvalid[SLAVE_PLIC]),
        .s_axi_rready (m_rready[SLAVE_PLIC]),
        .reg_wr       (plic_wr),
        .reg_waddr    (plic_waddr),
        .reg_wdata    (plic_wdata),
        .reg_wstrb    (plic_wstrb),
        .reg_rd       (plic_rd),
        .reg_raddr    (plic_raddr),
        .reg_rdata    (plic_rdata)
    );

    logic sdhci_irq;
    logic kbd_irq;
    logic mouse_irq;

    PLIC #(
        .num_sources (3),
        .num_contexts(2)
    ) plic (
        .clk      (clk),
        .reset    (reset),
        .sources  ({mouse_irq, kbd_irq, sdhci_irq}),
        .irq      (plic_irq),
        .reg_wr   (plic_wr),
        .reg_waddr(plic_waddr),
        .reg_wdata(plic_wdata),
        .reg_wstrb(plic_wstrb),
        .reg_rd   (plic_rd),
        .reg_raddr(plic_raddr),
        .reg_rdata(plic_rdata)
    );

    `define REG_BLOCK(name, slave) \
        logic        name``_wr; \
        logic [15:0] name``_waddr; \
        logic [31:0] name``_wdata; \
        logic [ 3:0] name``_wstrb; \
        logic        name``_rd; \
        logic [15:0] name``_raddr; \
        logic [31:0] name``_rdata; \
        AXILiteRegs #( \
            .addr_bits(16) \
        ) name``_regs ( \
            .clk          (clk), \
            .reset        (reset), \
            .s_axi_awaddr (m_awaddr[15:0]), \
            .s_axi_awvalid(m_awvalid[slave]), \
            .s_axi_awready(m_awready[slave]), \
            .s_axi_wdata  (m_wdata), \
            .s_axi_wstrb  (m_wstrb), \
            .s_axi_wvalid (m_wvalid[slave]), \
            .s_axi_wready (m_wready[slave]), \
            .s_axi_bvalid (m_bvalid[slave]), \
            .s_axi_bready (m_bready[slave]), \
            .s_axi_araddr (m_araddr[15:0]), \
            .s_axi_arvalid(m_arvalid[slave]), \
            .s_axi_arready(m_arready[slave]), \
            .s_axi_rdata  (m_rdata[slave*32+:32]), \
            .s_axi_rvalid (m_rvalid[slave]), \
            .s_axi_rready (m_rready[slave]), \
            .reg_wr       (name``_wr), \
            .reg_waddr    (name``_waddr), \
            .reg_wdata    (name``_wdata), \
            .reg_wstrb    (name``_wstrb), \
            .reg_rd       (name``_rd), \
            .reg_raddr    (name``_raddr), \
            .reg_rdata    (name``_rdata) \
        );

    `REG_BLOCK(debug, SLAVE_DEBUG)
    `REG_BLOCK(kbd, SLAVE_KBD)
    `REG_BLOCK(mouse, SLAVE_MOUSE)
    `REG_BLOCK(console, SLAVE_CONSOLE)

    ConsoleUART console (
        .clk       (clk),
        .reset     (reset),
        .reg_wr    (console_wr),
        .reg_waddr (console_waddr),
        .reg_wdata (console_wdata),
        .reg_wstrb (console_wstrb),
        .reg_rd    (console_rd),
        .reg_raddr (console_raddr),
        .reg_rdata (console_rdata),
        .read_addr (console_read_addr),
        .read_data (console_read_data),
        .byte_count(console_byte_count)
    );

    DebugRegs debug (
        .clk      (clk),
        .reset    (reset),
        .reg_wr   (debug_wr),
        .reg_waddr(debug_waddr),
        .reg_wdata(debug_wdata),
        .reg_wstrb(debug_wstrb),
        .reg_rd   (debug_rd),
        .reg_raddr(debug_raddr),
        .reg_rdata(debug_rdata),
        .leds     (leds),
        .hex_n    (hex_n)
    );

    AltPS2 #(
        .clk_freq(clk_freq)
    ) kbd (
        .clk        (clk),
        .reset      (reset),
        .irq        (kbd_irq),
        .reg_wr     (kbd_wr),
        .reg_waddr  (kbd_waddr),
        .reg_wdata  (kbd_wdata),
        .reg_wstrb  (kbd_wstrb),
        .reg_rd     (kbd_rd),
        .reg_raddr  (kbd_raddr),
        .reg_rdata  (kbd_rdata),
        .ps2_clk_i  (kbd_clk_i),
        .ps2_clk_low(kbd_clk_low),
        .ps2_dat_i  (kbd_dat_i),
        .ps2_dat_low(kbd_dat_low)
    );

    AltPS2 #(
        .clk_freq(clk_freq)
    ) mouse (
        .clk        (clk),
        .reset      (reset),
        .irq        (mouse_irq),
        .reg_wr     (mouse_wr),
        .reg_waddr  (mouse_waddr),
        .reg_wdata  (mouse_wdata),
        .reg_wstrb  (mouse_wstrb),
        .reg_rd     (mouse_rd),
        .reg_raddr  (mouse_raddr),
        .reg_rdata  (mouse_rdata),
        .ps2_clk_i  (mouse_clk_i),
        .ps2_clk_low(mouse_clk_low),
        .ps2_dat_i  (mouse_dat_i),
        .ps2_dat_low(mouse_dat_low)
    );

    // ------------------------------------------------------------------
    // SD host controller, its SDMA goes straight to the SDRAM DMA port.
    // ------------------------------------------------------------------
    // verilator lint_off UNUSEDSIGNAL
    logic [7:0] dma_awlen;
    logic [2:0] dma_awsize;
    logic [1:0] dma_awburst;
    logic [3:0] dma_awcache;
    logic [2:0] dma_awprot;
    logic [7:0] dma_arlen;
    logic [2:0] dma_arsize;
    logic [1:0] dma_arburst;
    logic [3:0] dma_arcache;
    logic [2:0] dma_arprot;
    // verilator lint_on UNUSEDSIGNAL

    assign x_bus.wlen = dma_awlen[3:0];
    assign x_bus.rlen = dma_arlen[3:0];

    SDHCI #(
        .tmclk_div     (clk_freq / 1000000),
        .dma_line_bytes(64)
    ) sdhci (
        .clk          (clk),
        .resetn       (~reset),
        .s_axi_awaddr (m_awaddr[15:0]),
        .s_axi_awvalid(m_awvalid[SLAVE_SDHCI]),
        .s_axi_awready(m_awready[SLAVE_SDHCI]),
        .s_axi_wdata  (m_wdata),
        .s_axi_wstrb  (m_wstrb),
        .s_axi_wvalid (m_wvalid[SLAVE_SDHCI]),
        .s_axi_wready (m_wready[SLAVE_SDHCI]),
        .s_axi_bresp  (sdhci_bresp),
        .s_axi_bvalid (m_bvalid[SLAVE_SDHCI]),
        .s_axi_bready (m_bready[SLAVE_SDHCI]),
        .s_axi_araddr (m_araddr[15:0]),
        .s_axi_arvalid(m_arvalid[SLAVE_SDHCI]),
        .s_axi_arready(m_arready[SLAVE_SDHCI]),
        .s_axi_rdata  (m_rdata[SLAVE_SDHCI*32+:32]),
        .s_axi_rresp  (sdhci_rresp),
        .s_axi_rvalid (m_rvalid[SLAVE_SDHCI]),
        .s_axi_rready (m_rready[SLAVE_SDHCI]),
        .irq          (sdhci_irq),
        .activity     (sd_activity),
        .m_axi_awaddr (x_bus.waddr),
        .m_axi_awlen  (dma_awlen),
        .m_axi_awsize (dma_awsize),
        .m_axi_awburst(dma_awburst),
        .m_axi_awcache(dma_awcache),
        .m_axi_awprot (dma_awprot),
        .m_axi_awvalid(x_bus.awvalid),
        .m_axi_awready(x_bus.awready),
        .m_axi_wdata  (x_bus.wdata),
        .m_axi_wstrb  (x_bus.wstb),
        .m_axi_wlast  (x_bus.wlast),
        .m_axi_wvalid (x_bus.wvalid),
        .m_axi_wready (x_bus.wready),
        .m_axi_bresp  (2'b00),
        .m_axi_bvalid (x_bus.bvalid),
        .m_axi_bready (x_bus.bready),
        .m_axi_araddr (x_bus.raddr),
        .m_axi_arlen  (dma_arlen),
        .m_axi_arsize (dma_arsize),
        .m_axi_arburst(dma_arburst),
        .m_axi_arcache(dma_arcache),
        .m_axi_arprot (dma_arprot),
        .m_axi_arvalid(x_bus.arvalid),
        .m_axi_arready(x_bus.arready),
        .m_axi_rdata  (x_bus.rdata),
        .m_axi_rresp  (2'b00),
        .m_axi_rlast  (x_bus.rlast),
        .m_axi_rvalid (x_bus.rvalid),
        .m_axi_rready (x_bus.rready),
        .sd_clk       (sd_clk),
        .cmd_o        (sd_cmd_o),
        .cmd_t        (sd_cmd_t),
        .cmd_i        (sd_cmd_i),
        .dat_o        (sd_dat_o),
        .dat_t        (sd_dat_t),
        .dat_i        (sd_dat_i),
        // There is no card detect on the DE0-CV.
        .cd_n         (1'b0)
    );

    // ------------------------------------------------------------------
    // Debug probe
    // ------------------------------------------------------------------
    logic [31:0] last_dev_addr;
    logic [15:0] i_requests;
    logic [15:0] d_requests;

    always_ff @(posedge clk) begin
        if (dev_bus.arvalid && dev_bus.arready) last_dev_addr <= dev_bus.raddr;
        if (dev_bus.awvalid && dev_bus.awready) last_dev_addr <= dev_bus.waddr;
        if (i_mem_bus.arvalid && i_mem_bus.arready) i_requests <= i_requests + 1'b1;
        if ((d_mem_bus.arvalid && d_mem_bus.arready) || (d_mem_bus.awvalid && d_mem_bus.awready))
            d_requests <= d_requests + 1'b1;
    end

    assign debug_probe = {debug_state[159:32], d_requests, i_requests, last_dev_addr,
                          27'b0, mouse_irq, kbd_irq, sdhci_irq, mtime_irq, plic_irq[1],
                          debug_state[31:0]};

endmodule
