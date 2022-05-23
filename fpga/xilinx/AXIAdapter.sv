module AXIAdapter (
    output wire                 [31:0] axi_awaddr,
    output wire                 [ 7:0] axi_awlen,
    output wire                 [ 2:0] axi_awsize,
    output wire                 [ 1:0] axi_awburst,
    output wire                        axi_awlock,
    output wire                 [ 3:0] axi_awcache,
    output wire                 [ 2:0] axi_awprot,
    output wire                 [ 3:0] axi_awregion,
    output wire                 [ 3:0] axi_awqos,
    output wire                        axi_awvalid,
    input  wire                        axi_awready,
    output wire                 [31:0] axi_wdata,
    output wire                 [ 3:0] axi_wstrb,
    output wire                        axi_wlast,
    output wire                        axi_wvalid,
    input  wire                        axi_wready,
    input  wire                        axi_bvalid,
    output wire                        axi_bready,
    output wire                 [31:0] axi_araddr,
    output wire                 [ 7:0] axi_arlen,
    output wire                 [ 2:0] axi_arsize,
    output wire                 [ 1:0] axi_arburst,
    output wire                        axi_arlock,
    output wire                 [ 3:0] axi_arcache,
    output wire                 [ 2:0] axi_arprot,
    output wire                 [ 3:0] axi_arregion,
    output wire                 [ 3:0] axi_arqos,
    output wire                        axi_arvalid,
    input  wire                        axi_arready,
    input  wire                 [31:0] axi_rdata,
    input  wire                        axi_rlast,
    input  wire                        axi_rvalid,
    output wire                        axi_rready,
    MemInterface.Subordinate    bus
);

    localparam AXI_SIZE_32B = 3'd2;
    localparam AXI_BURST_INCR = 2'b01;
    localparam AXI_CACHE_DEVICE = 4'b0000;
    localparam AXI_CACHE_WB = 4'b1111;

    assign axi_awaddr   = bus.waddr;
    assign axi_awlen    = {4'b0, bus.wlen};
    assign axi_awsize   = AXI_SIZE_32B;
    assign axi_awburst  = AXI_BURST_INCR;
    assign axi_awlock   = 1'b0;
    assign axi_awcache  = bus.wlen == 4'b0 ? AXI_CACHE_DEVICE : AXI_CACHE_WB;
    assign axi_awprot   = 3'b000;
    assign axi_awregion = 4'b0000;
    assign axi_awqos    = 4'b0000;
    assign axi_awvalid  = bus.awvalid;
    assign bus.awready  = axi_awready;
    assign axi_wdata    = bus.wdata;
    assign axi_wstrb    = bus.wstb;
    assign axi_wlast    = bus.wlast;
    assign axi_wvalid   = bus.wvalid;
    assign bus.wready   = axi_wready;

    assign bus.bvalid   = axi_bvalid;
    assign axi_bready   = bus.bready;

    assign axi_araddr   = bus.raddr;
    assign axi_arlen    = {4'b0, bus.rlen};
    assign axi_arsize   = AXI_SIZE_32B;
    assign axi_arburst  = AXI_BURST_INCR;
    assign axi_arlock   = 1'b0;
    assign axi_arcache  = bus.rlen == 4'b0 ? AXI_CACHE_DEVICE : AXI_CACHE_WB;
    assign axi_arprot   = 3'b000;
    assign axi_arregion = 4'b0000;
    assign axi_arqos    = 4'b0000;
    assign axi_arvalid  = bus.arvalid;
    assign bus.arready  = axi_arready;
    assign bus.rdata    = axi_rdata;
    assign bus.rlast    = axi_rlast;
    assign bus.rvalid   = axi_rvalid;
    assign axi_rready   = bus.rready;

endmodule
