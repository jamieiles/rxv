`default_nettype none

module RXVCoreSynthTop (
`ifdef USE_POWER_PINS
    inout               vccd1,
    inout               vssd1,
`endif
    input  logic        clk,
    input  logic        reset,
    // verilator lint_off UNUSED
    output logic [31:0] i_raddr,
    output logic [31:0] d_waddr,
    output logic [31:0] d_raddr,
    // verilator lint_on UNUSED
    input  logic        i_arready,
    output logic        i_arvalid,
    input  logic        i_rvalid,
    output logic        i_rready,
    input  logic [31:0] i_rdata,
    input  logic        i_rlast,
    output logic [ 3:0] i_rlen,
    input  logic        d_awready,
    output logic        d_awvalid,
    input  logic        d_arready,
    output logic        d_arvalid,
    output logic        d_wvalid,
    input  logic        d_wready,
    input  logic        d_rvalid,
    output logic        d_rready,
    output logic [ 3:0] d_wstb,
    output logic [31:0] d_wdata,
    input  logic [31:0] d_rdata,
    output logic        d_wlast,
    input  logic        d_rlast,
    output logic [ 3:0] d_rlen,
    output logic [ 3:0] d_wlen,
    output logic        d_bready,
    input  logic        d_bvalid,
    input  logic [63:0] mtime,
    input  logic        mtime_irq,
    input  logic        ext_irq
);

    MemInterface i_mem_bus ();
    MemInterface d_mem_bus ();

    assign i_raddr           = i_mem_bus.raddr;
    assign i_arvalid         = i_mem_bus.arvalid;
    assign i_rready          = i_mem_bus.rready;
    assign i_rlen            = i_mem_bus.rlen;
    assign i_mem_bus.awready = 1'b0;
    assign i_mem_bus.arready = i_arready;
    assign i_mem_bus.wready  = 1'b0;
    assign i_mem_bus.rvalid  = i_rvalid;
    assign i_mem_bus.rdata   = i_rdata;
    assign i_mem_bus.rlast   = i_rlast;
    assign i_mem_bus.bvalid  = 1'b0;

    assign d_waddr           = d_mem_bus.waddr;
    assign d_raddr           = d_mem_bus.raddr;
    assign d_awvalid         = d_mem_bus.awvalid;
    assign d_arvalid         = d_mem_bus.arvalid;
    assign d_wvalid          = d_mem_bus.wvalid;
    assign d_rready          = d_mem_bus.rready;
    assign d_wstb            = d_mem_bus.wstb;
    assign d_wdata           = d_mem_bus.wdata;
    assign d_wlast           = d_mem_bus.wlast;
    assign d_rlen            = d_mem_bus.rlen;
    assign d_wlen            = d_mem_bus.wlen;
    assign d_bready          = d_mem_bus.bready;
    assign d_mem_bus.awready = d_awready;
    assign d_mem_bus.arready = d_arready;
    assign d_mem_bus.wready  = d_wready;
    assign d_mem_bus.rvalid  = d_rvalid;
    assign d_mem_bus.rdata   = d_rdata;
    assign d_mem_bus.rlast   = d_rlast;
    assign d_mem_bus.bvalid  = d_bvalid;

    RXVCore #(
        .icache_nr_ways      (8),
        .icache_nr_lines     (128),
        .dcache_nr_ways      (8),
        .dcache_nr_lines     (128),
        .banked_register_file(0),
        .reset_address       (32'h40000000),
        .num_itlb_entries    (16),
        .num_dtlb_entries    (16)
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
