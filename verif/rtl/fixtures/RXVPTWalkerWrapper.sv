`default_nettype none

module RXVPTWalkerWrapper (
    input  logic         clk,
    input  logic         reset,
    input  logic [31:12] va,
    input  logic         valid,
    input  logic [31:12] translation_base,
    output logic         busy,
    output logic [ 31:0] pte_out,
    output logic         is_megapage,
    output logic         translation_error
);

    logic        dcache_valid;
    logic [31:0] dcache_dout;
    logic        dcache_busy;
    logic [31:2] dcache_address;

    MemInterface mem_bus ();

    BusTransactor BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVDCache RXVDCache (
        .clk          (clk),
        .reset        (reset),
        .address      (dcache_address),
        .valid        (dcache_valid),
        .busy         (dcache_busy),
        .din          (32'b0),
        .wren         (1'b0),
        .bytesel      (4'b1111),
        .dout         (dcache_dout),
        .invalidate   (1'b0),
        .clean        (1'b0),
        .bus          (mem_bus.Manager),
        // verilator lint_off PINCONNECTEMPTY
        .phys_out     (),
        // verilator lint_on PINCONNECTEMPTY
        .device_memory(1'b0)
    );

    RXVPTWalker RXVPTWalker (
        .clk              (clk),
        .reset            (reset),
        .va               (va),
        .valid            (valid),
        .translation_base (translation_base),
        .busy             (busy),
        .pte_out          (pte_out),
        .is_megapage      (is_megapage),
        .translation_error(translation_error),
        .dcache_address   (dcache_address),
        .dcache_valid     (dcache_valid),
        .dcache_busy      (dcache_busy),
        .dcache_rdata     (dcache_dout)
    );

endmodule
