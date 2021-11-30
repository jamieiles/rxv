`default_nettype none

import RXVTypes::commit_entry;

module RXVCommitBuffer #(
    parameter int order = 3
) (
    input  logic                         clk,
    input  logic                         reset,
    // Dispatch
    output logic                         full,
    input  commit_entry                  dispatch_in,
    input  logic                         dispatch_valid,
    output logic        [addr_width-1:0] dispatch_id,
    // Kill
    input  logic        [addr_width-1:0] kill_id,
    input  logic                         kill_valid,
    // Completion
    input  logic        [addr_width-1:0] complete_id,
    input  logic                         complete_valid,
    // Exception
    input  logic        [addr_width-1:0] except_id,
    input  logic                         except_valid,
    // Retirement
    output logic                         empty,
    output commit_entry                  commit_out,
    output logic                         commit_complete_out,
    output logic                         commit_killed_out,
    output logic                         commit_excepted_out,
    input  logic                         commit_valid,
    output logic        [addr_width-1:0] commit_id
);

    localparam int num_entries = (1 << order);
    localparam int addr_width = $clog2(num_entries);

    Fifo #(
        .data_width($bits(commit_entry)),
        .order     (order)
    ) commit_fifo (
        .clk    (clk),
        .reset  (reset),
        .flush  (1'b0),
        .wr_en  (dispatch_valid),
        .wr_data(dispatch_in),
        .wr_ptr (dispatch_id),
        .rd_en  (commit_valid),
        .rd_data(commit_out),
        .rd_ptr (commit_id),
        .empty  (empty),
        .full   (full)
    );

    logic [num_entries-1:0] completed;
    logic [num_entries-1:0] completed_next;

    logic [ addr_width-1:0] excepted_id;
    logic                   excepted;
    logic                   excepted_next;
    logic [ addr_width-1:0] killed_id;
    logic                   killed_id_valid;
    logic                   killed_id_valid_next;
    logic                   killed;
    logic                   killed_next;

    always_comb begin
        killed_next = killed;
        if (excepted && commit_id == excepted_id) killed_next = 1'b1;
        if (killed_id_valid && commit_id == killed_id) killed_next = 1'b1;
        if ((commit_valid && commit_id == killed_id && killed) || empty) killed_next = 1'b0;
    end

    always_comb begin
        killed_id_valid_next = killed_id_valid;
        if (commit_id == killed_id) killed_id_valid_next = 1'b0;
        if (kill_valid) killed_id_valid_next = 1'b1;
    end

    always_comb begin
        excepted_next = excepted;
        if ((commit_valid && commit_id == killed_id && killed) || empty) excepted_next = 1'b0;
        if (except_valid) excepted_next = 1'b1;
    end

    always_comb begin
        integer i;
        for (i = 0; i < num_entries; i = i + 1) begin
            completed_next[i] = completed[i];
            if (dispatch_id == addr_width'(i) && dispatch_valid) completed_next[i] = 1'b0;
            if (complete_id == addr_width'(i) && complete_valid) completed_next[i] = 1'b1;
            if (commit_id == addr_width'(i) && commit_valid) completed_next[i] = 1'b0;
        end
    end

    always_comb begin
        commit_complete_out = completed[commit_id];
        commit_killed_out   = killed || (killed_id_valid && killed_id == commit_id);
        commit_excepted_out = excepted && excepted_id == commit_id;
    end

`ifdef verilator
    always_ff @(posedge clk) begin
        if (full) assert (!dispatch_valid);
        if (empty) assert (!commit_valid);
    end
`endif

    RXVDFF #(
        .width(addr_width)
    ) excepted_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (except_valid),
        .d    (except_id),
        .q    (excepted_id)
    );

    RXVDFF #(
        .width(num_entries)
    ) completed_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (completed_next),
        .q    (completed)
    );

    RXVDFF #(
        .width(addr_width)
    ) killed_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (kill_valid),
        .d    (kill_id),
        .q    (killed_id)
    );

    RXVDFF killed_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (killed_next),
        .q    (killed)
    );

    RXVDFF killed_id_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (killed_id_valid_next),
        .q    (killed_id_valid)
    );

    RXVDFF excepted_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (excepted_next),
        .q    (excepted)
    );

endmodule
