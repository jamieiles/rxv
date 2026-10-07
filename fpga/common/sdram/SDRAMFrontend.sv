// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// Frontend for SDRAMController.
//
// Ports:
//   - ibus/dbus/xbus: instruction, data and DMA ports, whole cache lines
//     only, the same contract as MIGFrontend.  There is no coherence with
//     the CPU caches.
//   - vbus: video scanout, whole line reads only, takes priority over the
//     other ports.
//   - ubus: uncached single word accesses through a window in the device
//     address range (the framebuffer), relocated to u_dram_base.
//
// The controller executes one request at a time and all requests pass
// through a single slot in grant order, so reads and writes to the same
// address from any port are ordered without hazard checks.  A write is only
// issued once all of its data is in the write data FIFO; the write response
// is returned when the controller takes it as anything granted later
// executes after it.  Read data returns in request order into a FIFO that is
// credited at grant time and is unpacked to the requesting port.
module SDRAMFrontend #(
    parameter int                        line_size_bytes = 64,
    parameter int                        dram_addr_bits  = 26,
    parameter int                        rd_fifo_order   = 5,
    parameter int                        wr_fifo_order   = 5,
    parameter logic [              31:0] u_window_mask   = 32'h000fffff,
    parameter logic [dram_addr_bits-1:0] u_dram_base     = 26'h3f00000
) (
    input  logic                           clk,
    input  logic                           reset,
           MemInterface.Subordinate        ibus,
           MemInterface.Subordinate        dbus,
           MemInterface.Subordinate        xbus,
           MemInterface.Subordinate        vbus,
           MemInterface.Subordinate        ubus,
    // Controller
    input  logic                           init_done,
    output logic                           req_valid,
    input  logic                           req_ready,
    output logic                           req_write,
    output logic        [dram_addr_bits-1:2] req_addr,
    output logic        [               3:0] req_len,
    output logic        [              31:0] wr_data,
    output logic        [               3:0] wr_strb,
    input  logic                           wr_pop,
    input  logic                           rd_valid,
    input  logic        [              31:0] rd_data,
    // verilator lint_off UNUSED
    input  logic                           rd_last
    // verilator lint_on UNUSED
);

    localparam int rd_fifo_depth = 1 << rd_fifo_order;
    localparam int wr_fifo_depth = 1 << wr_fifo_order;
    localparam int pq_order = 3;
    localparam int pq_depth = 1 << pq_order;
    localparam logic [3:0] line_len = 4'((line_size_bytes / 4) - 1);

    initial assert (line_size_bytes == 64);
    initial assert (rd_fifo_depth >= 2 * (line_size_bytes / 4));
    initial assert (wr_fifo_depth >= 2 * (line_size_bytes / 4));

    localparam logic [2:0] PORT_I = 3'd0;
    localparam logic [2:0] PORT_D = 3'd1;
    localparam logic [2:0] PORT_X = 3'd2;
    localparam logic [2:0] PORT_V = 3'd3;
    localparam logic [2:0] PORT_U = 3'd4;

    // Round-robin request types, video reads have priority over these.
    localparam int REQ_I_RD = 0;
    localparam int REQ_D_RD = 1;
    localparam int REQ_D_WR = 2;
    localparam int REQ_X_RD = 3;
    localparam int REQ_X_WR = 4;
    localparam int REQ_U_RD = 5;
    localparam int REQ_U_WR = 6;
    localparam int num_reqs = 7;

    function automatic logic [2:0] rr_grant(input logic [num_reqs-1:0] req, input logic [2:0] last);
        logic [2:0] p;
        rr_grant = last;
        for (int k = num_reqs; k >= 1; --k) begin
            p = 3'((32'(last) + k) % num_reqs);
            if (req[p]) rr_grant = p;
        end
    endfunction

    // Slot
    logic                              slot_valid;
    logic                              slot_write;
    logic [                       2:0] slot_port;
    logic [          dram_addr_bits-1:2] slot_addr;
    logic [                       3:0] slot_len;
    logic [                       3:0] slot_words;
    logic                              slot_data_ready;

    // Grant
    logic [              num_reqs-1:0] req;
    logic [                       2:0] grant;
    logic [                       2:0] last_grant;
    logic                              grant_v;
    logic                              grant_rr;
    logic                              grant_fire;
    logic                              grant_write;
    logic [                       2:0] grant_port;
    logic [                      31:0] grant_cpu_addr;
    // verilator lint_off UNUSEDSIGNAL
    logic [          dram_addr_bits-1:0] grant_dram_addr;
    // verilator lint_on UNUSEDSIGNAL
    logic [                       3:0] grant_len;
    logic [                       3:0] i_rlen;
    logic [                       3:0] d_rlen;
    logic [                       3:0] x_rlen;
    logic [                       3:0] u_rlen;
    logic [                       3:0] d_wlen;
    logic [                       3:0] x_wlen;
    logic [                       3:0] u_wlen;
    logic                              line_credit_ok;
    logic                              word_credit_ok;
    logic                              line_wr_space_ok;
    logic                              word_wr_space_ok;
    logic [               rd_fifo_order:0] rd_credits;
    logic [               wr_fifo_order:0] wr_reserved;

    // Write data
    logic                              w_valid;
    logic [                      31:0] w_data;
    logic [                       3:0] w_strb;
    logic                              w_last;
    logic                              w_fire;
    logic [                      35:0] wr_fifo                 [wr_fifo_depth];
    logic [               wr_fifo_order:0] wr_fifo_wr_ptr;
    logic [               wr_fifo_order:0] wr_fifo_rd_ptr;

    // Write responses
    logic                              d_bvalid;
    logic                              x_bvalid;
    logic                              u_bvalid;

    // Issue
    logic                              issue;

    // Read data
    logic [                      31:0] rd_fifo                 [rd_fifo_depth];
    logic [               rd_fifo_order:0] rd_fifo_wr_ptr;
    logic [               rd_fifo_order:0] rd_fifo_rd_ptr;
    logic [                       6:0] pq                      [pq_depth];
    logic [                  pq_order:0] pq_wr_ptr;
    logic [                  pq_order:0] pq_rd_ptr;
    logic [                       2:0] out_port;
    logic [                       3:0] out_len;
    logic [                       3:0] out_word;
    logic                              out_valid;
    logic                              out_ready;
    logic                              out_fire;
    logic                              out_last;
    logic [                      31:0] out_data;

    // ------------------------------------------------------------------
    // Grant: one request into the slot when it is empty.  Ready signals
    // only depend on registered state and the valids, not the addresses.
    // ------------------------------------------------------------------
    always_comb begin
        i_rlen           = ibus.rlen;
        d_rlen           = dbus.rlen;
        x_rlen           = xbus.rlen;
        u_rlen           = ubus.rlen;
        d_wlen           = dbus.wlen;
        x_wlen           = xbus.wlen;
        u_wlen           = ubus.wlen;

        line_credit_ok   = rd_credits + (rd_fifo_order + 1)'(line_len) + 1'b1 <=
            (rd_fifo_order + 1)'(rd_fifo_depth);
        word_credit_ok   = rd_credits != (rd_fifo_order + 1)'(rd_fifo_depth);
        line_wr_space_ok = wr_reserved + (wr_fifo_order + 1)'(line_len) + 1'b1 <=
            (wr_fifo_order + 1)'(wr_fifo_depth);
        word_wr_space_ok = wr_reserved != (wr_fifo_order + 1)'(wr_fifo_depth);

        req              = '0;
        req[REQ_I_RD]    = ibus.arvalid && line_credit_ok;
        req[REQ_D_RD]    = dbus.arvalid && line_credit_ok;
        req[REQ_D_WR]    = dbus.awvalid && line_wr_space_ok && !d_bvalid;
        req[REQ_X_RD]    = xbus.arvalid && line_credit_ok;
        req[REQ_X_WR]    = xbus.awvalid && line_wr_space_ok && !x_bvalid;
        req[REQ_U_RD]    = ubus.arvalid && word_credit_ok;
        req[REQ_U_WR]    = ubus.awvalid && word_wr_space_ok && !u_bvalid;

        grant            = rr_grant(req, last_grant);
        grant_v          = vbus.arvalid && line_credit_ok;
        grant_rr         = !grant_v && |req;
        grant_fire       = !slot_valid && init_done && (grant_v || grant_rr);

        grant_write      = !grant_v && (grant == 3'(REQ_D_WR) || grant == 3'(REQ_X_WR) ||
                                        grant == 3'(REQ_U_WR));
        if (grant_v) grant_port = PORT_V;
        else begin
            unique case (32'(grant))
                REQ_I_RD: grant_port = PORT_I;
                REQ_D_RD, REQ_D_WR: grant_port = PORT_D;
                REQ_X_RD, REQ_X_WR: grant_port = PORT_X;
                default: grant_port = PORT_U;
            endcase
        end

        grant_len = line_len;
        unique case (grant_port)
            PORT_U: grant_len = 4'd0;
            default: ;
        endcase

        grant_cpu_addr = vbus.raddr;
        if (!grant_v) begin
            unique case (32'(grant))
                REQ_I_RD: grant_cpu_addr = ibus.raddr;
                REQ_D_RD: grant_cpu_addr = dbus.raddr;
                REQ_D_WR: grant_cpu_addr = dbus.waddr;
                REQ_X_RD: grant_cpu_addr = xbus.raddr;
                REQ_X_WR: grant_cpu_addr = xbus.waddr;
                REQ_U_RD: grant_cpu_addr = ubus.raddr;
                default:  grant_cpu_addr = ubus.waddr;
            endcase
        end

        grant_dram_addr = grant_port == PORT_U ?
            u_dram_base + dram_addr_bits'(grant_cpu_addr & u_window_mask) :
            grant_cpu_addr[dram_addr_bits-1:0];
    end

    assign vbus.arready = !slot_valid && init_done && grant_v;
    assign ibus.arready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_I_RD);
    assign dbus.arready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_D_RD);
    assign dbus.awready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_D_WR);
    assign xbus.arready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_X_RD);
    assign xbus.awready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_X_WR);
    assign ubus.arready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_U_RD);
    assign ubus.awready = !slot_valid && init_done && grant_rr && grant == 3'(REQ_U_WR);

    // ------------------------------------------------------------------
    // Write data: collected from the slot's port into the write FIFO.
    // ------------------------------------------------------------------
    always_comb begin
        unique case (slot_port)
            PORT_X: begin
                w_valid = xbus.wvalid;
                w_data  = xbus.wdata;
                w_strb  = xbus.wstb;
                w_last  = xbus.wlast;
            end
            PORT_U: begin
                w_valid = ubus.wvalid;
                w_data  = ubus.wdata;
                w_strb  = ubus.wstb;
                w_last  = ubus.wlast;
            end
            default: begin
                w_valid = dbus.wvalid;
                w_data  = dbus.wdata;
                w_strb  = dbus.wstb;
                w_last  = dbus.wlast;
            end
        endcase

        // Space was reserved when the write was granted.
        w_fire = slot_valid && slot_write && !slot_data_ready && w_valid;
    end

    assign dbus.wready = slot_valid && slot_write && !slot_data_ready && slot_port == PORT_D;
    assign xbus.wready = slot_valid && slot_write && !slot_data_ready && slot_port == PORT_X;
    assign ubus.wready = slot_valid && slot_write && !slot_data_ready && slot_port == PORT_U;

    always_ff @(posedge clk) begin
        if (w_fire) wr_fifo[wr_fifo_wr_ptr[wr_fifo_order-1:0]] <= {w_strb, w_data};
    end

    assign {wr_strb, wr_data} = wr_fifo[wr_fifo_rd_ptr[wr_fifo_order-1:0]];

    // ------------------------------------------------------------------
    // Issue to the controller
    // ------------------------------------------------------------------
    assign req_valid = slot_valid && (!slot_write || slot_data_ready);
    assign req_write = slot_write;
    assign req_addr  = slot_addr;
    assign req_len   = slot_len;
    assign issue     = req_valid && req_ready;

    assign dbus.bvalid = d_bvalid;
    assign xbus.bvalid = x_bvalid;
    assign ubus.bvalid = u_bvalid;

    always_ff @(posedge clk) begin
        if (grant_fire) begin
            slot_valid      <= 1'b1;
            slot_write      <= grant_write;
            slot_port       <= grant_port;
            slot_addr       <= grant_dram_addr[dram_addr_bits-1:2];
            slot_len        <= grant_len;
            slot_words      <= '0;
            slot_data_ready <= 1'b0;
            if (!grant_v) last_grant <= grant;
        end

        if (w_fire) begin
            slot_words <= slot_words + 1'b1;
            if (w_last || slot_words == slot_len) slot_data_ready <= 1'b1;
        end

        if (issue) slot_valid <= 1'b0;

        if (d_bvalid && dbus.bready) d_bvalid <= 1'b0;
        if (x_bvalid && xbus.bready) x_bvalid <= 1'b0;
        if (u_bvalid && ubus.bready) u_bvalid <= 1'b0;
        if (issue && slot_write) begin
            if (slot_port == PORT_D) d_bvalid <= 1'b1;
            if (slot_port == PORT_X) x_bvalid <= 1'b1;
            if (slot_port == PORT_U) u_bvalid <= 1'b1;
        end

        rd_credits <= rd_credits +
            (grant_fire && !grant_write ? (rd_fifo_order + 1)'(grant_len) + 1'b1 : '0) -
            (rd_fifo_order + 1)'(out_fire);
        wr_reserved <= wr_reserved +
            (grant_fire && grant_write ? (wr_fifo_order + 1)'(grant_len) + 1'b1 : '0) -
            (wr_fifo_order + 1)'(wr_pop);

        if (w_fire) wr_fifo_wr_ptr <= wr_fifo_wr_ptr + 1'b1;
        if (wr_pop) wr_fifo_rd_ptr <= wr_fifo_rd_ptr + 1'b1;

        if (reset) begin
            slot_valid     <= 1'b0;
            last_grant     <= '0;
            d_bvalid       <= 1'b0;
            x_bvalid       <= 1'b0;
            u_bvalid       <= 1'b0;
            rd_credits     <= '0;
            wr_reserved    <= '0;
            wr_fifo_wr_ptr <= '0;
            wr_fifo_rd_ptr <= '0;
        end
    end

    // ------------------------------------------------------------------
    // Read data: FIFO from the controller, port queue in request order
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rd_valid) rd_fifo[rd_fifo_wr_ptr[rd_fifo_order-1:0]] <= rd_data;
        if (issue && !slot_write) pq[pq_wr_ptr[pq_order-1:0]] <= {slot_port, slot_len};
    end

    always_comb begin
        {out_port, out_len} = pq[pq_rd_ptr[pq_order-1:0]];
        out_valid = rd_fifo_wr_ptr != rd_fifo_rd_ptr;
        unique case (out_port)
            PORT_D:  out_ready = dbus.rready;
            PORT_X:  out_ready = xbus.rready;
            PORT_V:  out_ready = vbus.rready;
            PORT_U:  out_ready = ubus.rready;
            default: out_ready = ibus.rready;
        endcase
        out_fire = out_valid && out_ready;
        out_last = out_word == out_len;
        out_data = rd_fifo[rd_fifo_rd_ptr[rd_fifo_order-1:0]];
    end

    assign ibus.rvalid = out_valid && out_port == PORT_I;
    assign dbus.rvalid = out_valid && out_port == PORT_D;
    assign xbus.rvalid = out_valid && out_port == PORT_X;
    assign vbus.rvalid = out_valid && out_port == PORT_V;
    assign ubus.rvalid = out_valid && out_port == PORT_U;
    assign ibus.rdata  = out_data;
    assign dbus.rdata  = out_data;
    assign xbus.rdata  = out_data;
    assign vbus.rdata  = out_data;
    assign ubus.rdata  = out_data;
    assign ibus.rlast  = out_last;
    assign dbus.rlast  = out_last;
    assign xbus.rlast  = out_last;
    assign vbus.rlast  = out_last;
    assign ubus.rlast  = out_last;

    always_ff @(posedge clk) begin
        if (rd_valid) rd_fifo_wr_ptr <= rd_fifo_wr_ptr + 1'b1;
        if (issue && !slot_write) pq_wr_ptr <= pq_wr_ptr + 1'b1;
        if (out_fire) begin
            rd_fifo_rd_ptr <= rd_fifo_rd_ptr + 1'b1;
            out_word       <= out_last ? 4'd0 : out_word + 1'b1;
            if (out_last) pq_rd_ptr <= pq_rd_ptr + 1'b1;
        end

        if (reset) begin
            rd_fifo_wr_ptr <= '0;
            rd_fifo_rd_ptr <= '0;
            pq_wr_ptr      <= '0;
            pq_rd_ptr      <= '0;
            out_word       <= '0;
        end
    end

    // The instruction and video ports never write
    assign ibus.awready = 1'b0;
    assign ibus.wready  = 1'b0;
    assign ibus.bvalid  = 1'b0;
    assign vbus.awready = 1'b0;
    assign vbus.wready  = 1'b0;
    assign vbus.bvalid  = 1'b0;

    RXVAssert #(
        .message("SDRAMFrontend: line port access is not a full line")
    ) full_line (
        .clk      (clk),
        .en       (grant_fire && grant_port != PORT_U),
        .condition(grant_v ? vbus.rlen == line_len :
                   grant == 3'(REQ_I_RD) ? i_rlen == line_len :
                   grant == 3'(REQ_D_RD) ? d_rlen == line_len :
                   grant == 3'(REQ_D_WR) ? d_wlen == line_len :
                   grant == 3'(REQ_X_RD) ? x_rlen == line_len : x_wlen == line_len)
    );

    RXVAssert #(
        .message("SDRAMFrontend: uncached access is not a single word")
    ) single_word (
        .clk      (clk),
        .en       (grant_fire && grant_port == PORT_U),
        .condition(grant == 3'(REQ_U_RD) ? u_rlen == 4'd0 : u_wlen == 4'd0)
    );

    RXVAssert #(
        .message("SDRAMFrontend: write on a read only port")
    ) no_read_only_write (
        .clk      (clk),
        .en       (!reset),
        .condition(!ibus.awvalid && !ibus.wvalid && !vbus.awvalid && !vbus.wvalid)
    );

    RXVAssert #(
        .message("SDRAMFrontend: port queue overflow")
    ) pq_no_overflow (
        .clk      (clk),
        .en       (issue && !slot_write && !reset),
        .condition(pq_wr_ptr != {~pq_rd_ptr[pq_order], pq_rd_ptr[pq_order-1:0]})
    );

endmodule
