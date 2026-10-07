// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// Terasic DE0-CV: clocking, reset and the I/O buffers around DE0CVSoC.
module DE0CVTop #(
    parameter bootrom_init = ""
) (
    input  wire        CLOCK_50,
    input  wire        RESET_N,
    // SDRAM
    output wire        DRAM_CLK,
    output wire        DRAM_CKE,
    output wire        DRAM_CS_N,
    output wire        DRAM_RAS_N,
    output wire        DRAM_CAS_N,
    output wire        DRAM_WE_N,
    output wire [ 1:0] DRAM_BA,
    output wire [12:0] DRAM_ADDR,
    output wire        DRAM_LDQM,
    output wire        DRAM_UDQM,
    inout  wire [15:0] DRAM_DQ,
    // microSD
    output wire        SD_CLK,
    inout  wire        SD_CMD,
    inout  wire [ 3:0] SD_DATA,
    // PS/2, keyboard on the first port and mouse on the second through a Y
    // cable
    inout  wire        PS2_CLK,
    inout  wire        PS2_DAT,
    inout  wire        PS2_CLK2,
    inout  wire        PS2_DAT2,
    // VGA
    output wire [ 3:0] VGA_R,
    output wire [ 3:0] VGA_G,
    output wire [ 3:0] VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    // Debug
    output wire [ 9:0] LEDR,
    output wire [ 6:0] HEX0,
    output wire [ 6:0] HEX1,
    output wire [ 6:0] HEX2,
    output wire [ 6:0] HEX3,
    output wire [ 6:0] HEX4,
    output wire [ 6:0] HEX5
);

    wire        sys_clk;
    wire        vga_clk;
    wire        clint_clk;
    wire        pll_locked;

    DE0CVPLL pll (
        .refclk   (CLOCK_50),
        .reset    (1'b0),
        .sys_clk  (sys_clk),
        .sdram_clk(DRAM_CLK),
        .vga_clk  (vga_clk),
        .clint_clk(clint_clk),
        .locked   (pll_locked)
    );

    // ------------------------------------------------------------------
    // Reset: held after power up, the PLL locking, the reset button or a
    // reset requested through the syscon register.
    // ------------------------------------------------------------------
    reg  [1:0] reset_n_sync = 2'b00;
    reg  [7:0] reset_count = 8'hff;
    reg        reset_req_last = 1'b0;
    wire       sys_reset_req;
    wire       reset = reset_count != 8'h00;
    reg  [1:0] vga_reset_sync = 2'b11;

    always @(posedge sys_clk) begin
        reset_n_sync   <= {reset_n_sync[0], RESET_N};
        reset_req_last <= sys_reset_req;

        if (!pll_locked || !reset_n_sync[1] || (sys_reset_req && !reset_req_last))
            reset_count <= 8'hff;
        else if (reset_count != 8'h00)
            reset_count <= reset_count - 1'b1;
    end

    always @(posedge vga_clk) vga_reset_sync <= {vga_reset_sync[0], reset};

    // ------------------------------------------------------------------
    // I/O
    // ------------------------------------------------------------------
    wire [15:0] s_dq_o;
    wire        s_dq_oe;
    wire [ 1:0] s_dqm;
    wire        sd_cmd_o;
    wire        sd_cmd_t;
    wire [ 3:0] sd_dat_o;
    wire [ 3:0] sd_dat_t;
    wire        kbd_clk_low;
    wire        kbd_dat_low;
    wire        mouse_clk_low;
    wire        mouse_dat_low;
    wire [41:0] hex_n;
    // verilator lint_off UNUSEDSIGNAL
    wire        sd_activity;
    // verilator lint_on UNUSEDSIGNAL

    assign DRAM_DQ   = s_dq_oe ? s_dq_o : 16'bz;
    assign DRAM_LDQM = s_dqm[0];
    assign DRAM_UDQM = s_dqm[1];

    // The SD tristate controls are active low enables.
    assign SD_CMD    = sd_cmd_t ? 1'bz : sd_cmd_o;
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_sd_dat
            assign SD_DATA[i] = sd_dat_t[i] ? 1'bz : sd_dat_o[i];
        end
    endgenerate

    assign PS2_CLK  = kbd_clk_low ? 1'b0 : 1'bz;
    assign PS2_DAT  = kbd_dat_low ? 1'b0 : 1'bz;
    assign PS2_CLK2 = mouse_clk_low ? 1'b0 : 1'bz;
    assign PS2_DAT2 = mouse_dat_low ? 1'b0 : 1'bz;

    assign {HEX5, HEX4, HEX3, HEX2, HEX1, HEX0} = hex_n;

    DE0CVSoC #(
        .clk_freq    (60000000),
        .bootrom_init(bootrom_init)
    ) soc (
        .clk          (sys_clk),
        .reset        (reset),
        .sys_reset_req(sys_reset_req),
        .clint_refclk (clint_clk),
        .s_cke        (DRAM_CKE),
        .s_cs_n       (DRAM_CS_N),
        .s_ras_n      (DRAM_RAS_N),
        .s_cas_n      (DRAM_CAS_N),
        .s_we_n       (DRAM_WE_N),
        .s_ba         (DRAM_BA),
        .s_addr       (DRAM_ADDR),
        .s_dqm        (s_dqm),
        .s_dq_o       (s_dq_o),
        .s_dq_oe      (s_dq_oe),
        .s_dq_i       (DRAM_DQ),
        .sd_clk       (SD_CLK),
        .sd_cmd_o     (sd_cmd_o),
        .sd_cmd_t     (sd_cmd_t),
        .sd_cmd_i     (SD_CMD),
        .sd_dat_o     (sd_dat_o),
        .sd_dat_t     (sd_dat_t),
        .sd_dat_i     (SD_DATA),
        .sd_activity  (sd_activity),
        .kbd_clk_i    (PS2_CLK),
        .kbd_clk_low  (kbd_clk_low),
        .kbd_dat_i    (PS2_DAT),
        .kbd_dat_low  (kbd_dat_low),
        .mouse_clk_i  (PS2_CLK2),
        .mouse_clk_low(mouse_clk_low),
        .mouse_dat_i  (PS2_DAT2),
        .mouse_dat_low(mouse_dat_low),
        .vga_clk      (vga_clk),
        .vga_reset    (vga_reset_sync[1]),
        .vga_r        (VGA_R),
        .vga_g        (VGA_G),
        .vga_b        (VGA_B),
        .vga_hsync    (VGA_HS),
        .vga_vsync    (VGA_VS),
        .leds         (LEDR),
        .hex_n        (hex_n)
    );

endmodule
