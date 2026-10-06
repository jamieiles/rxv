// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
//
// Block design wrapper for the SD host controller: IP integrator module
// references must have a Verilog top level.  The s_axi_ naming lets the
// AXI4-Lite interface, clock and reset be inferred.
module SDHCIAXI (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,
    input  wire [15:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [ 1:0] s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [15:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [ 1:0] s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire        irq,
    output wire        activity,
    // SDCLK is a register output, not a clock in the block design.
    (* X_INTERFACE_IGNORE = "true" *)
    output wire        sd_clk,
    output wire        sd_cmd_o,
    output wire        sd_cmd_t,
    input  wire        sd_cmd_i,
    output wire [ 3:0] sd_dat_o,
    output wire [ 3:0] sd_dat_t,
    input  wire [ 3:0] sd_dat_i,
    input  wire        sd_cd_n
);

    SDHCI sdhci (
        .clk          (s_axi_aclk),
        .resetn       (s_axi_aresetn),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .irq          (irq),
        .activity     (activity),
        .sd_clk       (sd_clk),
        .cmd_o        (sd_cmd_o),
        .cmd_t        (sd_cmd_t),
        .cmd_i        (sd_cmd_i),
        .dat_o        (sd_dat_o),
        .dat_t        (sd_dat_t),
        .dat_i        (sd_dat_i),
        .cd_n         (sd_cd_n)
    );

endmodule
