// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
interface MemInterface;

    // verilator lint_off UNUSED
    wire [31:0] waddr;
    wire [31:0] raddr;
    // verilator lint_on UNUSED
    wire        awready;
    wire        awvalid;
    wire        arready;
    wire        arvalid;
    wire        wvalid;
    wire        wready;
    wire        rvalid;
    wire        rready;
    wire [ 3:0] wstb;
    wire [31:0] wdata;
    wire [31:0] rdata;
    wire        wlast;
    wire        rlast;
    wire [ 3:0] rlen;
    wire [ 3:0] wlen;
    wire        bready;
    wire        bvalid;

    modport Manager(
        output waddr,
        output raddr,
        input awready,
        output awvalid,
        input arready,
        output arvalid,
        output rlen,
        output wlen,
        output wvalid,
        input wready,
        output wdata,
        output wstb,
        output wlast,
        input rvalid,
        output rready,
        input rdata,
        input rlast,
        output bready,
        input bvalid
    );

    modport Subordinate(
        input waddr,
        input raddr,
        output awready,
        input awvalid,
        output arready,
        input arvalid,
        input rlen,
        input wlen,
        input wvalid,
        output wready,
        input wstb,
        input wdata,
        input wlast,
        output rvalid,
        input rready,
        output rdata,
        output rlast,
        input bready,
        output bvalid
    );

endinterface
