module RXVCoreEmulWrapper (
    input logic clk,
    input logic reset
);

    MemInterface imem_bus ();
    MemInterface dmem_bus ();
    logic [63:0] mtime;
    logic        mtime_irq;

    BusTransactor IBusTransactor (
        .clk(clk),
        .bus(imem_bus.Subordinate)
    );

    BusTransactor DBusTransactor (
        .clk(clk),
        .bus(dmem_bus.Subordinate)
    );

    MtimeTransactor MtimeTransactor (
        .mtime    (mtime),
        .mtime_irq(mtime_irq)
    );

    RXVCore #(
        .icache_line_size_bytes(32),
        .dcache_line_size_bytes(32),
        .vendorid(32'h53454c49)
    ) RXVCore (
        .clk            (clk),
        .reset          (reset),
        .instruction_bus(imem_bus.Manager),
        .data_bus       (dmem_bus.Manager),
        .mtime          (mtime),
        .mtime_irq      (mtime_irq)
    );

endmodule
