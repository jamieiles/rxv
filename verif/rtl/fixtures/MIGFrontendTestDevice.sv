// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// Simple single-cycle device on the non-DRAM side of the split.  Read data is
// a function of the address so the test can check it.
module MIGFrontendTestDevice (
    input  logic                    clk,
    input  logic                    reset,
           MemInterface.Subordinate bus,
    output logic             [31:0] last_waddr,
    output logic             [31:0] last_wdata,
    output logic             [ 3:0] last_wstb,
    output logic             [ 7:0] write_count
);

    logic        r_active;
    logic [31:0] r_addr;
    logic [ 3:0] r_remaining;
    logic        w_active;
    logic        bvalid;

    assign bus.arready = !r_active;
    assign bus.rvalid  = r_active;
    assign bus.rdata   = r_addr ^ 32'h5a5a5a5a;
    assign bus.rlast   = r_active && r_remaining == 4'b0;
    assign bus.awready = !w_active;
    assign bus.wready  = w_active;
    assign bus.bvalid  = bvalid;

    always_ff @(posedge clk) begin
        if (bus.arvalid && bus.arready) begin
            r_active    <= 1'b1;
            r_addr      <= bus.raddr;
            r_remaining <= bus.rlen;
        end else if (r_active && bus.rready) begin
            r_addr      <= r_addr + 32'd4;
            r_remaining <= r_remaining - 1'b1;
            if (r_remaining == 4'b0) r_active <= 1'b0;
        end

        if (bus.awvalid && bus.awready) begin
            w_active   <= 1'b1;
            last_waddr <= bus.waddr;
        end

        if (bus.wvalid && bus.wready) begin
            last_wdata  <= bus.wdata;
            last_wstb   <= bus.wstb;
            write_count <= write_count + 1'b1;
            if (bus.wlast) begin
                w_active <= 1'b0;
                bvalid   <= 1'b1;
            end
        end

        if (bvalid && bus.bready) bvalid <= 1'b0;

        if (reset) begin
            r_active    <= 1'b0;
            w_active    <= 1'b0;
            bvalid      <= 1'b0;
            write_count <= 8'b0;
        end
    end

endmodule
