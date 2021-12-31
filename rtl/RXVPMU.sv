`default_nettype none

module RXVPMU (
    input  logic        clk,
    input  logic        reset,
    input  logic        retire_valid,
    input  logic        cyclesh_wren,
    input  logic        cyclesl_wren,
    input  logic        instreth_wren,
    input  logic        instretl_wren,
    input  logic [31:0] csr_wrval,
    output logic [63:0] pmu_cycles /* verilator public */,
    output logic [63:0] pmu_instret /* verilator public */
);

    logic [63:0] pmu_cycles_next;
    logic [63:0] pmu_instret_next;
    logic        pmu_instret_update;

    always_comb begin
        pmu_cycles_next = pmu_cycles + 1'b1;
        if (cyclesh_wren) pmu_cycles_next = {csr_wrval, pmu_cycles[31:0]};
        if (cyclesl_wren) pmu_cycles_next = {pmu_cycles[63:32], csr_wrval};
    end

    always_comb begin
        pmu_instret_next = pmu_instret + 1'b1;
        if (instreth_wren) pmu_instret_next = {csr_wrval, pmu_instret[31:0]};
        if (instretl_wren) pmu_instret_next = {pmu_instret[63:32], csr_wrval};

        pmu_instret_update = instreth_wren | instretl_wren | retire_valid;
    end

    RXVDFF #(
        .width(64)
    ) pmu_cycles_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (pmu_cycles_next),
        .q    (pmu_cycles)
    );

    RXVDFF #(
        .width(64)
    ) pmu_instret_dff (
        .clk  (clk),
        .reset(reset),
        .en   (pmu_instret_update),
        .d    (pmu_instret_next),
        .q    (pmu_instret)
    );

endmodule
