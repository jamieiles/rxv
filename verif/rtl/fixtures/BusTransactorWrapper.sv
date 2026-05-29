// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
// verilator lint_off UNDRIVEN
module BusTransactorWrapper (
    input  logic        clk,
    // verilator lint_off UNUSED
    input  logic        reset,
    // verilator lint_off UNUSED
    input  logic [31:0] waddr,
    input  logic [31:0] raddr,
    output logic        awready,
    input  logic        awvalid,
    output logic        arready,
    input  logic        arvalid,
    input  logic        wvalid,
    output logic        wready,
    output logic        rvalid,
    input  logic        rready,
    input  logic [ 3:0] wstb,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    input  logic        wlast,
    output logic        rlast,
    input  logic [ 3:0] rlen,
    input  logic [ 3:0] wlen,
    input  logic        bready,
    output logic        bvalid
);

    MemInterface mem_bus ();

    assign mem_bus.waddr = waddr;
    assign mem_bus.raddr = raddr;
    assign mem_bus.awvalid = awvalid;
    assign mem_bus.arvalid = arvalid;
    assign mem_bus.rlen = rlen;
    assign mem_bus.wlen = wlen;
    assign mem_bus.wvalid = wvalid;
    assign mem_bus.wstb = wstb;
    assign mem_bus.wdata = wdata;
    assign mem_bus.wlast = wlast;
    assign mem_bus.rready = rready;
    assign mem_bus.bready = bready;
    assign awready = mem_bus.awready;
    assign arready = mem_bus.arready;
    assign wready = mem_bus.wready;
    assign rvalid = mem_bus.rvalid;
    assign rdata = mem_bus.rdata;
    assign rlast = mem_bus.rlast;
    assign bvalid = mem_bus.bvalid;

    BusTransactor #(
        .instruction(1'b0)
    ) BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

endmodule
