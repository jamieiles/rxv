module RXVRegisterAllocator #(
    parameter  num_regs  = 32,
    localparam addr_bits = $clog2(num_regs)
) (
    input  logic                 clk,
    input  logic                 reset,
    // Consumer
    output logic                 empty,
    input  logic                 pop,
    output logic [addr_bits-1:0] pop_reg,
    // Producer
    input  logic                 push,
    input  logic [addr_bits-1:0] push_reg
);

    logic [ num_regs-1:0] free_map;
    logic [ num_regs-1:0] free_map_next;
    logic                 empty_next;
    logic [addr_bits-1:0] pop_reg_next;

    always_comb begin
        free_map_next = free_map;
        if (push) free_map_next[push_reg] = 1'b1;
        if (pop) free_map_next[pop_reg] = 1'b0;
        empty_next = ~|free_map_next;
    end

    always_comb begin
        integer i;

        pop_reg_next = 'b0;
        for (i = num_regs - 1; i >= 0; i = i - 1)
            if (free_map_next[i]) pop_reg_next = addr_bits'(i);
    end

    DFF empty_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (empty_next),
        .q    (empty)
    );

    DFF #(
        .width(addr_bits)
    ) pop_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (pop_reg_next),
        .q    (pop_reg)
    );

    DFF #(
        .width    (num_regs),
        .reset_val({num_regs{1'b1}})
    ) free_map_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (free_map_next),
        .q    (free_map)
    );

`ifdef verilator
    /*
     * Ensure that we don't push an free register or pop one that is
     * already allocated.
     */
    always_ff @(posedge clk) begin
        if (push) assert (!free_map[push_reg]);
        if (pop) assert (free_map[pop_reg]);
    end
`endif  // verilator

endmodule
