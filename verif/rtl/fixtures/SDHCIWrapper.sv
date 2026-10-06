// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// SDHCI with an active-high reset for the test driver, a fast timeout clock
// and a short card detect debounce to keep simulations short.
module SDHCIWrapper (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [ 3:0] s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [ 1:0] s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [15:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [ 1:0] s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,
    output logic        irq,
    output logic        activity,
    output logic        sd_clk,
    output logic        cmd_o,
    output logic        cmd_t,
    input  logic        cmd_i,
    output logic [ 3:0] dat_o,
    output logic [ 3:0] dat_t,
    input  logic [ 3:0] dat_i,
    input  logic        cd_n
);

    SDHCI #(
        .tmclk_div    (2),
        .debounce_bits(4)
    ) sdhci (
        .clk(clk),
        .resetn(~reset),
        .*
    );

endmodule
