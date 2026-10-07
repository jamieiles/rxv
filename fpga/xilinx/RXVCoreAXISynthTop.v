// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
module RXVCoreAXISynthTop (
    // verilog_format: off
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 core_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_RESET reset, ASSOCIATED_BUSIF m_i_axi:m_d_axi:s_dma_axi" *)
    input  wire         clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.reset RST" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.reset, POLARITY ACTIVE_HIGH, TYPE INTERCONNECT" *)
    input  wire         reset,
    // verilog_format: on
    output wire  [31:0] m_i_axi_awaddr,
    output wire  [ 7:0] m_i_axi_awlen,
    output wire  [ 2:0] m_i_axi_awsize,
    output wire  [ 1:0] m_i_axi_awburst,
    output wire         m_i_axi_awlock,
    output wire  [ 3:0] m_i_axi_awcache,
    output wire  [ 2:0] m_i_axi_awprot,
    output wire  [ 3:0] m_i_axi_awregion,
    output wire  [ 3:0] m_i_axi_awqos,
    output wire         m_i_axi_awvalid,
    input  wire         m_i_axi_awready,
    output wire  [31:0] m_i_axi_wdata,
    output wire  [ 3:0] m_i_axi_wstrb,
    output wire         m_i_axi_wlast,
    output wire         m_i_axi_wvalid,
    input  wire         m_i_axi_wready,
    // verilator lint_off UNUSED
    input  wire  [ 1:0] m_i_axi_bresp,
    // verilator lint_on UNUSED
    input  wire         m_i_axi_bvalid,
    output wire         m_i_axi_bready,
    output wire  [31:0] m_i_axi_araddr,
    output wire  [ 7:0] m_i_axi_arlen,
    output wire  [ 2:0] m_i_axi_arsize,
    output wire  [ 1:0] m_i_axi_arburst,
    output wire         m_i_axi_arlock,
    output wire  [ 3:0] m_i_axi_arcache,
    output wire  [ 2:0] m_i_axi_arprot,
    output wire  [ 3:0] m_i_axi_arregion,
    output wire  [ 3:0] m_i_axi_arqos,
    output wire         m_i_axi_arvalid,
    input  wire         m_i_axi_arready,
    input  wire  [31:0] m_i_axi_rdata,
    // verilator lint_off UNUSED
    input  wire  [ 1:0] m_i_axi_rresp,
    // verilator lint_on UNUSED
    input  wire         m_i_axi_rlast,
    input  wire         m_i_axi_rvalid,
    output wire         m_i_axi_rready,

    output wire [31:0] m_d_axi_awaddr,
    output wire [ 7:0] m_d_axi_awlen,
    output wire [ 2:0] m_d_axi_awsize,
    output wire [ 1:0] m_d_axi_awburst,
    output wire        m_d_axi_awlock,
    output wire [ 3:0] m_d_axi_awcache,
    output wire [ 2:0] m_d_axi_awprot,
    output wire [ 3:0] m_d_axi_awregion,
    output wire [ 3:0] m_d_axi_awqos,
    output wire        m_d_axi_awvalid,
    input  wire        m_d_axi_awready,
    output wire [31:0] m_d_axi_wdata,
    output wire [ 3:0] m_d_axi_wstrb,
    output wire        m_d_axi_wlast,
    output wire        m_d_axi_wvalid,
    input  wire        m_d_axi_wready,
    input  wire [ 1:0] m_d_axi_bresp,
    input  wire        m_d_axi_bvalid,
    output wire        m_d_axi_bready,
    output wire [31:0] m_d_axi_araddr,
    output wire [ 7:0] m_d_axi_arlen,
    output wire [ 2:0] m_d_axi_arsize,
    output wire [ 1:0] m_d_axi_arburst,
    output wire        m_d_axi_arlock,
    output wire [ 3:0] m_d_axi_arcache,
    output wire [ 2:0] m_d_axi_arprot,
    output wire [ 3:0] m_d_axi_arregion,
    output wire [ 3:0] m_d_axi_arqos,
    output wire        m_d_axi_arvalid,
    input  wire        m_d_axi_arready,
    input  wire [31:0] m_d_axi_rdata,
    input  wire [ 1:0] m_d_axi_rresp,
    input  wire        m_d_axi_rlast,
    input  wire        m_d_axi_rvalid,
    output wire        m_d_axi_rready,
    // DMA into DRAM from other bus managers.  Only whole, line aligned 16 beat
    // INCR bursts are supported, they go straight to the MIG frontend with
    // no coherence with the CPU caches.
    // verilog_format: off
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_dma_axi AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_dma_axi, PROTOCOL AXI4, DATA_WIDTH 32, ADDR_WIDTH 32, ID_WIDTH 0, MAX_BURST_LENGTH 16, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, HAS_LOCK 0, HAS_CACHE 0, HAS_PROT 0, HAS_QOS 0, HAS_REGION 0" *)
    // verilog_format: on
    input  wire [31:0] s_dma_axi_awaddr,
    input  wire [ 7:0] s_dma_axi_awlen,
    // verilator lint_off UNUSED
    input  wire [ 2:0] s_dma_axi_awsize,
    input  wire [ 1:0] s_dma_axi_awburst,
    // verilator lint_on UNUSED
    input  wire        s_dma_axi_awvalid,
    output wire        s_dma_axi_awready,
    input  wire [31:0] s_dma_axi_wdata,
    input  wire [ 3:0] s_dma_axi_wstrb,
    input  wire        s_dma_axi_wlast,
    input  wire        s_dma_axi_wvalid,
    output wire        s_dma_axi_wready,
    output wire [ 1:0] s_dma_axi_bresp,
    output wire        s_dma_axi_bvalid,
    input  wire        s_dma_axi_bready,
    input  wire [31:0] s_dma_axi_araddr,
    input  wire [ 7:0] s_dma_axi_arlen,
    // verilator lint_off UNUSED
    input  wire [ 2:0] s_dma_axi_arsize,
    input  wire [ 1:0] s_dma_axi_arburst,
    // verilator lint_on UNUSED
    input  wire        s_dma_axi_arvalid,
    output wire        s_dma_axi_arready,
    output wire [31:0] s_dma_axi_rdata,
    output wire [ 1:0] s_dma_axi_rresp,
    output wire        s_dma_axi_rlast,
    output wire        s_dma_axi_rvalid,
    input  wire        s_dma_axi_rready,
    input  wire [63:0] mtime,
    input  wire        mtime_irq,
    input  wire        ext_irq,
    // DDR3 controller, MIG native interface
    input  wire         ddr_calib_complete,
    output wire [ 27:0] ddr_app_addr,
    output wire [  2:0] ddr_app_cmd,
    output wire         ddr_app_en,
    input  wire         ddr_app_rdy,
    output wire [127:0] ddr_app_wdf_data,
    output wire [ 15:0] ddr_app_wdf_mask,
    output wire         ddr_app_wdf_wren,
    output wire         ddr_app_wdf_end,
    input  wire         ddr_app_wdf_rdy,
    input  wire [127:0] ddr_app_rd_data,
    input  wire         ddr_app_rd_data_valid,
    input  wire         ddr_app_rd_data_end
);

    MemInterface i_mem_bus ();
    MemInterface d_mem_bus ();
    MemInterface i_dram_bus ();
    MemInterface d_dram_bus ();
    MemInterface i_axi_bus ();
    MemInterface d_axi_bus ();
    MemInterface x_dram_bus ();

    // The DMA port is a direct mapping of AXI4 (without IDs) onto the
    // frontend, the burst length is checked there.
    assign x_dram_bus.raddr     = s_dma_axi_araddr;
    assign x_dram_bus.rlen      = s_dma_axi_arlen[3:0];
    assign x_dram_bus.arvalid   = s_dma_axi_arvalid;
    assign s_dma_axi_arready    = x_dram_bus.arready;
    assign s_dma_axi_rdata      = x_dram_bus.rdata;
    assign s_dma_axi_rresp      = 2'b00;
    assign s_dma_axi_rlast      = x_dram_bus.rlast;
    assign s_dma_axi_rvalid     = x_dram_bus.rvalid;
    assign x_dram_bus.rready    = s_dma_axi_rready;
    assign x_dram_bus.waddr     = s_dma_axi_awaddr;
    assign x_dram_bus.wlen      = s_dma_axi_awlen[3:0];
    assign x_dram_bus.awvalid   = s_dma_axi_awvalid;
    assign s_dma_axi_awready    = x_dram_bus.awready;
    assign x_dram_bus.wdata     = s_dma_axi_wdata;
    assign x_dram_bus.wstb      = s_dma_axi_wstrb;
    assign x_dram_bus.wlast     = s_dma_axi_wlast;
    assign x_dram_bus.wvalid    = s_dma_axi_wvalid;
    assign s_dma_axi_wready     = x_dram_bus.wready;
    assign s_dma_axi_bresp      = 2'b00;
    assign s_dma_axi_bvalid     = x_dram_bus.bvalid;
    assign x_dram_bus.bready    = s_dma_axi_bready;

    // DRAM is always accessed as whole cache lines so it bypasses AXI and
    // goes straight to the MIG native interface, everything else (boot ROM
    // and peripherals) stays on AXI.
    MemSplit #(
        .match_base(32'h80000000),
        .match_mask(32'hf0000000)
    ) i_split (
        .upstream(i_mem_bus.Subordinate),
        .match   (i_dram_bus.Manager),
        .other   (i_axi_bus.Manager)
    );

    MemSplit #(
        .match_base(32'h80000000),
        .match_mask(32'hf0000000)
    ) d_split (
        .upstream(d_mem_bus.Subordinate),
        .match   (d_dram_bus.Manager),
        .other   (d_axi_bus.Manager)
    );

    MIGFrontend #(
        .line_size_bytes(64),
        .app_addr_width (28)
    ) mig_frontend (
        .clk                (clk),
        .reset              (reset),
        .ibus               (i_dram_bus.Subordinate),
        .dbus               (d_dram_bus.Subordinate),
        .xbus               (x_dram_bus.Subordinate),
        .init_calib_complete(ddr_calib_complete),
        .app_addr           (ddr_app_addr),
        .app_cmd            (ddr_app_cmd),
        .app_en             (ddr_app_en),
        .app_rdy            (ddr_app_rdy),
        .app_wdf_data       (ddr_app_wdf_data),
        .app_wdf_mask       (ddr_app_wdf_mask),
        .app_wdf_wren       (ddr_app_wdf_wren),
        .app_wdf_end        (ddr_app_wdf_end),
        .app_wdf_rdy        (ddr_app_wdf_rdy),
        .app_rd_data        (ddr_app_rd_data),
        .app_rd_data_valid  (ddr_app_rd_data_valid),
        .app_rd_data_end    (ddr_app_rd_data_end)
    );

    AXIAdapter axi_i (
        .axi_awaddr  (m_i_axi_awaddr),
        .axi_awlen   (m_i_axi_awlen),
        .axi_awsize  (m_i_axi_awsize),
        .axi_awburst (m_i_axi_awburst),
        .axi_awlock  (m_i_axi_awlock),
        .axi_awcache (m_i_axi_awcache),
        .axi_awprot  (m_i_axi_awprot),
        .axi_awregion(m_i_axi_awregion),
        .axi_awqos   (m_i_axi_awqos),
        .axi_awvalid (m_i_axi_awvalid),
        .axi_awready (m_i_axi_awready),
        .axi_wdata   (m_i_axi_wdata),
        .axi_wstrb   (m_i_axi_wstrb),
        .axi_wlast   (m_i_axi_wlast),
        .axi_wvalid  (m_i_axi_wvalid),
        .axi_wready  (m_i_axi_wready),
        .axi_bvalid  (m_i_axi_bvalid),
        .axi_bready  (m_i_axi_bready),
        .axi_araddr  (m_i_axi_araddr),
        .axi_arlen   (m_i_axi_arlen),
        .axi_arsize  (m_i_axi_arsize),
        .axi_arburst (m_i_axi_arburst),
        .axi_arlock  (m_i_axi_arlock),
        .axi_arcache (m_i_axi_arcache),
        .axi_arprot  (m_i_axi_arprot),
        .axi_arregion(m_i_axi_arregion),
        .axi_arqos   (m_i_axi_arqos),
        .axi_arvalid (m_i_axi_arvalid),
        .axi_arready (m_i_axi_arready),
        .axi_rdata   (m_i_axi_rdata),
        .axi_rlast   (m_i_axi_rlast),
        .axi_rvalid  (m_i_axi_rvalid),
        .axi_rready  (m_i_axi_rready),
        .bus         (i_axi_bus)
    );

    AXIAdapter axi_d (
        .axi_awaddr  (m_d_axi_awaddr),
        .axi_awlen   (m_d_axi_awlen),
        .axi_awsize  (m_d_axi_awsize),
        .axi_awburst (m_d_axi_awburst),
        .axi_awlock  (m_d_axi_awlock),
        .axi_awcache (m_d_axi_awcache),
        .axi_awprot  (m_d_axi_awprot),
        .axi_awregion(m_d_axi_awregion),
        .axi_awqos   (m_d_axi_awqos),
        .axi_awvalid (m_d_axi_awvalid),
        .axi_awready (m_d_axi_awready),
        .axi_wdata   (m_d_axi_wdata),
        .axi_wstrb   (m_d_axi_wstrb),
        .axi_wlast   (m_d_axi_wlast),
        .axi_wvalid  (m_d_axi_wvalid),
        .axi_wready  (m_d_axi_wready),
        .axi_bvalid  (m_d_axi_bvalid),
        .axi_bready  (m_d_axi_bready),
        .axi_araddr  (m_d_axi_araddr),
        .axi_arlen   (m_d_axi_arlen),
        .axi_arsize  (m_d_axi_arsize),
        .axi_arburst (m_d_axi_arburst),
        .axi_arlock  (m_d_axi_arlock),
        .axi_arcache (m_d_axi_arcache),
        .axi_arprot  (m_d_axi_arprot),
        .axi_arregion(m_d_axi_arregion),
        .axi_arqos   (m_d_axi_arqos),
        .axi_arvalid (m_d_axi_arvalid),
        .axi_arready (m_d_axi_arready),
        .axi_rdata   (m_d_axi_rdata),
        .axi_rlast   (m_d_axi_rlast),
        .axi_rvalid  (m_d_axi_rvalid),
        .axi_rready  (m_d_axi_rready),
        .bus         (d_axi_bus)
    );

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
    ) RXVCore (
        .clk            (clk),
        .reset          (reset),
        .instruction_bus(i_mem_bus.Manager),
        .data_bus       (d_mem_bus.Manager),
        .mtime          (mtime),
        .mtime_irq      (mtime_irq),
        .ext_irq        (ext_irq)
    );

endmodule
