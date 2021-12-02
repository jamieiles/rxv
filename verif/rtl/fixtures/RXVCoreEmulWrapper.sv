module RXVCoreEmulWrapper (
    input logic clk,
    input logic reset
);

    MemInterface imem_bus ();
    MemInterface dmem_bus ();

    BusTransactor IBusTransactor (
        .clk(clk),
        .bus(imem_bus.Subordinate)
    );

    BusTransactor DBusTransactor (
        .clk(clk),
        .bus(dmem_bus.Subordinate)
    );

    RXVCore #(
        .icache_line_size_bytes(32),
        .dcache_line_size_bytes(32)
    ) RXVCore (
        .clk            (clk),
        .reset          (reset),
        .instruction_bus(imem_bus.Manager),
        .data_bus       (dmem_bus.Manager)
    );

endmodule
