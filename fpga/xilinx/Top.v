// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`timescale 1ns / 1ps

module Top (
    input  wire        clk,
    input  wire        ext_reset,
    input  wire        uart_rtl_0_rxd,
    output wire        uart_rtl_0_txd,
    output wire [13:0] ddr3_addr,
    output wire [ 2:0] ddr3_ba,
    output wire        ddr3_cas_n,
    output wire        ddr3_ck_n,
    output wire        ddr3_ck_p,
    output wire        ddr3_cke,
    output wire        ddr3_cs_n,
    output wire [ 1:0] ddr3_dm,
    inout       [15:0] ddr3_dq,
    inout       [ 1:0] ddr3_dqs_n,
    inout       [ 1:0] ddr3_dqs_p,
    output wire        ddr3_odt,
    output wire        ddr3_ras_n,
    output wire        ddr3_reset_n,
    output wire        ddr3_we_n,
    input  wire        sd_miso,
    output wire        sd_mosi,
    output wire        sd_ncs,
    output wire        sd_sck,
    output wire        sd_busy,
    input  wire        eth_miso,
    output wire        eth_mosi,
    output wire        eth_ncs,
    output wire        eth_sck,
    input  wire        eth_int,
    output wire        eth_reset
);

    wire        reset_rtl_0;
    wire        uart_rtl_0_baudoutn;
    wire        uart_rtl_0_ctsn;
    wire        uart_rtl_0_dcdn;
    wire        uart_rtl_0_ddis;
    wire        uart_rtl_0_dsrn;
    wire        uart_rtl_0_dtrn;
    wire        uart_rtl_0_out1n;
    wire        uart_rtl_0_out2n;
    wire        uart_rtl_0_ri;
    wire        uart_rtl_0_rtsn;
    wire        uart_rtl_0_rxrdyn;
    wire        uart_rtl_0_txrdyn;

    wire [15:0] bootrom_bram_addr;
    wire        bootrom_bram_clk;
    wire [31:0] bootrom_bram_din;
    wire [31:0] bootrom_bram_dout;
    wire        bootrom_bram_en;
    wire [ 3:0] bootrom_bram_we;

    wire        sd_busy_counter_reload;
    wire        sd_busy_expired;

    wire        spi_miso;
    wire        spi_mosi;
    wire [ 1:0] spi_ncs;
    wire        spi_sck;

    assign sd_busy   = ~sd_busy_expired;
    assign sd_mosi   = spi_mosi;
    assign sd_ncs    = spi_ncs[0];
    assign sd_sck    = spi_sck;

    assign eth_mosi  = spi_mosi;
    assign eth_ncs   = spi_ncs[1];
    assign eth_sck   = spi_sck;
    assign eth_reset = 1'b1;

    assign spi_miso  = ~sd_ncs ? sd_miso : ~eth_ncs ? eth_miso : 1'b1;

    RXVCountdown #(
        .width     (22),
        .reload_val(22'h3fffff)
    ) sd_busy_counter (
        .clk    (bootrom_bram_clk),
        .reset  (1'b0),
        .reload (~sd_ncs),
        .expired(sd_busy_expired)
    );

    wire rst_pulse;

    RXVCountdown #(
        .width     (8),
        .reload_val(8'hff)
    ) reset_counter (
        .clk    (rst_clk),
        .reset  (1'b0),
        .reload (mmio_rst_sync & ~mmio_rst_sync_last),
        .expired(rst_pulse)
    );

    xpm_memory_spram #(
        .ADDR_WIDTH_A      (14),
        .BYTE_WRITE_WIDTH_A(8),
        .MEMORY_PRIMITIVE  ("block"),
        .MEMORY_SIZE       (16384 * 32),
        .READ_DATA_WIDTH_A (32),
        .READ_LATENCY_A    (1),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_MODE_A      ("write_first"),
        .MEMORY_INIT_FILE  ("bootrom.mem"),
        .MEMORY_INIT_PARAM ("")
    ) ram (
        .addra (bootrom_bram_addr[15:2]),
        .clka  (bootrom_bram_clk),
        .dina  (bootrom_bram_din),
        .douta (bootrom_bram_dout),
        .ena   (bootrom_bram_en),
        .rsta  (1'b0),
        .wea   (bootrom_bram_we),
        .regcea(1'b1),
        .sleep (1'b0)
    );


    wire                                      sys_clk;
    wire                                      rst_clk;
    wire                                      mmio_rst;
    wire                                      mmio_rst_sync;
    reg                                       mmio_rst_sync_last;

    wire rtl_reset = ~ext_reset | ~rst_pulse;

    always @(posedge rst_clk) mmio_rst_sync_last <= mmio_rst_sync;

    BitSync mmio_rst_bitsync (
        .clk  (rst_clk),
        .reset(1'b0),
        .d    (mmio_rst),
        .q    (mmio_rst_sync)
    );

    BUFG sys_bufg (
        .I(clk),
        .O(sys_clk)
    );

    BUFG rst_bufg (
        .I(clk),
        .O(rst_clk)
    );

    RXVArty_wrapper inst (
        .clk_100MHz         (sys_clk),
        .pwr_on_rst         (pwr_on_rst),
        .reset_rtl_0        (rtl_reset),
        .uart_rtl_0_baudoutn(),
        .uart_rtl_0_ctsn    (),
        .uart_rtl_0_dcdn    (),
        .uart_rtl_0_ddis    (),
        .uart_rtl_0_dsrn    (),
        .uart_rtl_0_dtrn    (),
        .uart_rtl_0_out1n   (),
        .uart_rtl_0_out2n   (),
        .uart_rtl_0_ri      (),
        .uart_rtl_0_rtsn    (),
        .uart_rtl_0_rxd     (uart_rtl_0_rxd),
        .uart_rtl_0_rxrdyn  (),
        .uart_rtl_0_txd     (uart_rtl_0_txd),
        .uart_rtl_0_txrdyn  (),
        .bootrom_bram_addr  (bootrom_bram_addr),
        .bootrom_bram_clk   (bootrom_bram_clk),
        .bootrom_bram_din   (bootrom_bram_din),
        .bootrom_bram_dout  (bootrom_bram_dout),
        .bootrom_bram_en    (bootrom_bram_en),
        .bootrom_bram_we    (bootrom_bram_we),
        .ddr3_addr          (ddr3_addr),
        .ddr3_ba            (ddr3_ba),
        .ddr3_cas_n         (ddr3_cas_n),
        .ddr3_ck_n          (ddr3_ck_n),
        .ddr3_ck_p          (ddr3_ck_p),
        .ddr3_cke           (ddr3_cke),
        .ddr3_cs_n          (ddr3_cs_n),
        .ddr3_dm            (ddr3_dm),
        .ddr3_dq            (ddr3_dq),
        .ddr3_dqs_n         (ddr3_dqs_n),
        .ddr3_dqs_p         (ddr3_dqs_p),
        .ddr3_odt           (ddr3_odt),
        .ddr3_ras_n         (ddr3_ras_n),
        .ddr3_reset_n       (ddr3_reset_n),
        .ddr3_we_n          (ddr3_we_n),
        .spi_miso           (spi_miso),
        .spi_mosi           (spi_mosi),
        .spi_ncs            (spi_ncs),
        .spi_sck            (spi_sck),
        .eth_int            (eth_int),
        .mmio_rst           (mmio_rst)
    );

endmodule
