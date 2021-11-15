module RXVDCacheWrapper #(
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
    input  logic [31:0] din,
    input  logic        wren,
    input  logic [ 3:0] bytesel,
    output logic [31:0] dout,
    input  logic        invalidate,
    input  logic        clean
);

    logic [31:0] phys_out;
    logic        device_memory;

    MemInterface mem_bus ();

    BusTransactor BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVDCache #(
        .nr_lines       (nr_lines),
        .nr_ways        (nr_ways),
        .line_size_bytes(line_size_bytes)
    ) RXVDCache (
        .clk          (clk),
        .reset        (reset),
        .address      (address),
        .valid        (valid),
        .busy         (busy),
        .din          (din),
        .wren         (wren),
        .bytesel      (bytesel),
        .dout         (dout),
        .invalidate   (invalidate),
        .clean        (clean),
        .bus          (mem_bus.Manager),
        .phys_out     (phys_out),
        .device_memory(device_memory)
    );

    always_comb begin
        device_memory = &phys_out[31:28];
    end

endmodule
