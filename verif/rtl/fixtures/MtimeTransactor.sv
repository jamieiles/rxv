module MtimeTransactor (
    output logic [63:0] mtime,
    output logic        mtime_irq
);

    logic [63:0] mtimecmp_reg  /* verilator public */;
    logic [63:0] mtime_reg  /* verilator public */;

    always_comb begin
        mtime_irq = mtime_reg > mtimecmp_reg;
        mtime     = mtime_reg;
    end

endmodule
