`include "RXV.svh"
module BusAdapter (
    input  logic                       clk,
    input  logic                       reset,
           MemInterface.Manager        bus,
    input  logic                       valid,
    output logic                       complete,
    input  logic                [31:2] address,
    input  logic                [31:0] wdata,
    input  logic                       wren,
    input  logic                [ 3:0] bytesel,
    output logic                [31:0] rdata,
    input  logic                [ 3:0] len,
    output logic                [ 3:0] beat_num,
    output logic                [ 3:0] beat_num_next,
    output logic                       beat_ack
);

    assign bus.wdata  = wdata;
    assign bus.bready = 1'b1;
    assign bus.rready = 1'b1;

    logic        arvalid_next;
    logic        awvalid_next;
    logic        wvalid_next;
    logic        wlast_next;
    logic [31:2] address_f;
    logic        bus_active_next;
    logic        bus_active;
    logic [ 3:0] len_f;
    logic        bus_ar_ack;
    logic        bus_aw_ack;
    logic        bus_write_ack;
    logic        bus_write_beat_ack;
    logic        bus_read_beat_ack;

    always_comb begin
        bus_ar_ack         = bus.arready & bus.arvalid;
        bus_aw_ack         = bus.awready & bus.awvalid;
        bus_write_ack      = bus.bready & bus.bvalid;
        bus_write_beat_ack = bus.wready & bus.wvalid;
        bus_read_beat_ack  = bus.rready & bus.rvalid;
    end

    assign bus.rlen  = len_f;
    assign bus.wlen  = len_f;
    assign bus.raddr = {address_f, 2'b0};
    assign bus.waddr = {address_f, 2'b0};

    always_comb begin
        wvalid_next = bus.wvalid;

        if (bus_ar_ack) begin
            arvalid_next = 1'b0;
        end else if (bus.arvalid) begin
            arvalid_next = 1'b1;
        end else begin
            arvalid_next = ~wren & valid & ~bus_active;
        end

        if (bus_aw_ack) begin
            awvalid_next = 1'b0;
            wvalid_next  = 1'b1;
        end else if (bus.awvalid) begin
            awvalid_next = 1'b1;
        end else begin
            awvalid_next = wren & valid & ~bus_active;
        end

        if (bus_write_beat_ack & bus.wlast) begin
            wvalid_next = 1'b0;
        end

        beat_num_next = bus_read_beat_ack || bus_write_beat_ack ? beat_num + 1'b1 : beat_num;
        wlast_next = beat_num_next == len_f ? wvalid_next : bus_write_beat_ack ? 1'b0 : bus.wlast;
        beat_ack = bus_read_beat_ack | bus_write_beat_ack;
        bus_active_next = complete ? 1'b0 : valid | bus_active;

        rdata = bus.rdata;
        if (complete) beat_num_next = 'b0;
    end

    always_comb begin
        complete = bus_write_ack | (bus.rlast & bus_read_beat_ack);
    end

    RXVDFF bus_active_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bus_active_next),
        .q    (bus_active)
    );

    RXVDFF #(
        .width(4)
    ) beat_num_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (beat_num_next),
        .q    (beat_num)
    );

    RXVDFF arvalid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (arvalid_next),
        .q    (bus.arvalid)
    );

    RXVDFF awvalid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (awvalid_next),
        .q    (bus.awvalid)
    );

    RXVDFF wvalid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wvalid_next),
        .q    (bus.wvalid)
    );

    RXVDFF wlast_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (wlast_next),
        .q    (bus.wlast)
    );

    RXVDFF #(
        .width(30)
    ) addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (valid),
        .d    (address),
        .q    (address_f)
    );

    RXVDFF #(
        .width(4)
    ) len_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (len),
        .q    (len_f)
    );

    RXVDFF #(
        .width(4)
    ) wstb_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bytesel),
        .q    (bus.wstb)
    );

endmodule
