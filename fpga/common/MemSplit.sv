// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
// Steer transactions from a single manager to one of two subordinates based
// on the address.  Addresses matching (addr & match_mask) == match_base go to
// the "match" port, everything else goes to the "other" port.
//
// This relies on the BusAdapter properties that there is only ever one
// transaction in flight and that the address is held stable for the duration
// of the transaction so the select can be purely combinational.  Write
// responses are not waited on by the manager so bready is driven to both
// subordinates to allow a late bvalid to drain even if the select has moved
// on.
module MemSplit #(
    parameter logic [31:0] match_base = 32'h80000000,
    parameter logic [31:0] match_mask = 32'hf0000000
) (
    MemInterface.Subordinate upstream,
    MemInterface.Manager     match,
    MemInterface.Manager     other
);

    logic sel_r;
    logic sel_w;

    always_comb begin
        sel_r = (upstream.raddr & match_mask) == match_base;
        sel_w = (upstream.waddr & match_mask) == match_base;
    end

    // Read address and data
    assign match.raddr      = upstream.raddr;
    assign other.raddr      = upstream.raddr;
    assign match.rlen       = upstream.rlen;
    assign other.rlen       = upstream.rlen;
    assign match.arvalid    = upstream.arvalid & sel_r;
    assign other.arvalid    = upstream.arvalid & ~sel_r;
    assign upstream.arready = sel_r ? match.arready : other.arready;
    assign match.rready     = upstream.rready & sel_r;
    assign other.rready     = upstream.rready & ~sel_r;
    assign upstream.rvalid  = sel_r ? match.rvalid : other.rvalid;
    assign upstream.rdata   = sel_r ? match.rdata : other.rdata;
    assign upstream.rlast   = sel_r ? match.rlast : other.rlast;

    // Write address and data
    assign match.waddr      = upstream.waddr;
    assign other.waddr      = upstream.waddr;
    assign match.wlen       = upstream.wlen;
    assign other.wlen       = upstream.wlen;
    assign match.wdata      = upstream.wdata;
    assign other.wdata      = upstream.wdata;
    assign match.wstb       = upstream.wstb;
    assign other.wstb       = upstream.wstb;
    assign match.wlast      = upstream.wlast;
    assign other.wlast      = upstream.wlast;
    assign match.awvalid    = upstream.awvalid & sel_w;
    assign other.awvalid    = upstream.awvalid & ~sel_w;
    assign upstream.awready = sel_w ? match.awready : other.awready;
    assign match.wvalid     = upstream.wvalid & sel_w;
    assign other.wvalid     = upstream.wvalid & ~sel_w;
    assign upstream.wready  = sel_w ? match.wready : other.wready;

    // Write response
    assign match.bready     = upstream.bready;
    assign other.bready     = upstream.bready;
    assign upstream.bvalid  = sel_w ? match.bvalid : other.bvalid;

endmodule
