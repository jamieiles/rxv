`default_nettype none

/*
 * Static priority cache arbiter.  MMU takes priority to guarantee forward
 * progress, interlocks at issue time ensure that there will be no ITLB fills
 * during an LSU operation and vice versa.
 */
module RXVDCacheArb (
    input  logic        clk,
    input  logic        reset,
    // From LSU
    input  logic [31:2] lsu_dcache_address,
    input  logic        lsu_dcache_valid,
    output logic        lsu_dcache_busy,
    output logic [31:0] lsu_dcache_rdata,
    input  logic        lsu_dcache_wren,
    input  logic [ 3:0] lsu_dcache_bytesel,
    input  logic [31:0] lsu_dcache_wdata,
    input  logic [31:2] lsu_dcache_phys_in,
    input  logic        lsu_dcache_phys_valid,
    input  logic        lsu_dcache_invalidate,
    input  logic        lsu_dcache_clean,
    // From MMU
    input  logic [31:2] mmu_dcache_address,
    input  logic        mmu_dcache_valid,
    output logic        mmu_dcache_busy,
    output logic [31:0] mmu_dcache_rdata,
    input  logic [31:2] mmu_dcache_phys_in,
    input  logic        mmu_dcache_phys_valid,
    // To/From Cache
    output logic [31:2] dcache_address,
    output logic        dcache_valid,
    input  logic        dcache_busy,
    input  logic [31:0] dcache_rdata,
    output logic        dcache_wren,
    output logic [ 3:0] dcache_bytesel,
    output logic [31:0] dcache_wdata,
    output logic [31:2] dcache_phys_in,
    output logic        dcache_phys_valid,
    output logic        dcache_invalidate,
    output logic        dcache_clean
);

    logic lsu_dcache_grant;
    logic mmu_dcache_grant;
    logic lsu_dcache_grant_sync;
    logic mmu_dcache_grant_sync;
    logic lsu_dcache_req;

    RXVAssert no_cache_contention (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(mmu_dcache_valid && lsu_dcache_valid))
    );

    StaticArbiter #(
        .width(2)
    ) CacheArb (
        .clk    (clk),
        .reset  (reset),
        .request({lsu_dcache_req, mmu_dcache_valid}),
        .hold   (dcache_busy),
        .grant  ({lsu_dcache_grant, mmu_dcache_grant})
    );

    always_comb begin
        lsu_dcache_req = lsu_dcache_valid | lsu_dcache_invalidate | lsu_dcache_clean;
    end

    always_comb begin
        dcache_address    = lsu_dcache_grant ? lsu_dcache_address : mmu_dcache_address;
        dcache_valid      = lsu_dcache_grant ? lsu_dcache_valid : mmu_dcache_valid;
        dcache_invalidate = lsu_dcache_grant ? lsu_dcache_invalidate : 1'b0;
        dcache_clean      = lsu_dcache_grant ? lsu_dcache_clean : 1'b0;
        dcache_wren       = lsu_dcache_grant_sync ? lsu_dcache_wren : 1'b0;
        dcache_bytesel    = lsu_dcache_grant_sync ? lsu_dcache_bytesel : 4'b0;
        dcache_wdata      = lsu_dcache_grant_sync ? lsu_dcache_wdata : 32'b0;
        dcache_phys_in    = lsu_dcache_grant_sync ? lsu_dcache_phys_in : mmu_dcache_phys_in;
        dcache_phys_valid = lsu_dcache_grant_sync ? lsu_dcache_phys_valid : mmu_dcache_phys_valid;

        mmu_dcache_busy   = mmu_dcache_grant_sync ? dcache_busy : 1'b0;
        lsu_dcache_busy   = lsu_dcache_grant_sync ? dcache_busy : 1'b0;

        mmu_dcache_rdata  = dcache_rdata;
        lsu_dcache_rdata  = dcache_rdata;
    end

    RXVDFF lsu_dcache_grant_sync_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_dcache_grant),
        .q    (lsu_dcache_grant_sync)
    );

    RXVDFF mmu_dcache_grant_sync_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (mmu_dcache_grant),
        .q    (mmu_dcache_grant_sync)
    );

endmodule
