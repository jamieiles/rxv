module RXVICacheWrapper #(
    parameter nr_lines        = 4,
    parameter nr_ways         = 4,
    parameter line_size_bytes = 16
) (
    input  logic        clk,
    input  logic        reset,
    // CPU
    input  logic [31:2] address,
    input  logic        valid,
    output logic        busy,
    output logic [31:0] dout,
    input  logic        invalidate,
    output logic        pmu_icache_access,
    output logic        pmu_icache_miss,
    input  logic [31:2] phys_in,
    input  logic        phys_valid
);

    MemInterface mem_bus ();

    BusTransactor #(
        .instruction(1'b1)
    ) BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVICache #(
        .nr_lines       (nr_lines),
        .nr_ways        (nr_ways),
        .line_size_bytes(line_size_bytes)
    ) RXVICache (
        .clk              (clk),
        .reset            (reset),
        .address          (address),
        .valid            (valid),
        .busy             (busy),
        .dout             (dout),
        .invalidate       (invalidate),
        .pmu_icache_access(pmu_icache_access),
        .pmu_icache_miss  (pmu_icache_miss),
        .bus              (mem_bus.Manager),
        .phys_in          (phys_in),
        .phys_valid       (phys_valid)
    );

endmodule
