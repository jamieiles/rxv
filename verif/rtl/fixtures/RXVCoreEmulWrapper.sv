module RXVCoreEmulWrapper (
    input logic clk,
    input logic reset
);

    MemInterface mem_bus ();

    BusTransactor BusTransactor (
        .clk(clk),
        .bus(mem_bus.Subordinate)
    );

    RXVCore RXVCore (
        .clk            (clk),
        .reset          (reset),
        .instruction_bus(mem_bus.Manager)
    );

endmodule
