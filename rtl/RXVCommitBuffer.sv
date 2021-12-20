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
    input  logic                         kill_valid,
    // Completion
    input  logic        [addr_width-1:0] complete_id,
    input  logic                         complete_valid,
    // Exception
    input  logic        [addr_width-1:0] except_id,
    input  logic                         except_valid,
    output logic                         exception_pending,
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
    logic [num_entries-1:0] killed;
    logic [num_entries-1:0] killed_next;
    logic [num_entries-1:0] excepted;
    logic [num_entries-1:0] excepted_next;

    logic                   killing;
    logic                   killing_next;
    logic                   exception_pending_next;

    always_comb begin
        killing_next = killing;
        if (commit_valid && excepted[commit_id]) killing_next = 1'b1;
        if (~|killed) killing_next = 1'b0;
    end

    always_comb begin
        integer i;
        for (i = 0; i < num_entries; i = i + 1) begin
            excepted_next[i] = excepted[i];
            if (dispatch_id == addr_width'(i) && dispatch_valid) excepted_next[i] = 1'b0;
            if (except_id == addr_width'(i) && except_valid) excepted_next[i] = 1'b1;
            if (commit_id == addr_width'(i) && commit_valid) excepted_next[i] = 1'b0;
        end
    end

    always_comb begin
        integer i;
        for (i = 0; i < num_entries; i = i + 1) begin
            killed_next[i] = killed[i];
            if (dispatch_id == addr_width'(i) && dispatch_valid) killed_next[i] = 1'b0;
            if (dispatch_id - 1'b1 == addr_width'(i) && kill_valid) killed_next[i] = 1'b1;
            if (except_id == addr_width'(i) && except_valid) killed_next[i] = 1'b1;
            if (commit_id == addr_width'(i) && commit_valid) killed_next[i] = 1'b0;
        end
    end

    RXVAssert #(
        .message("no kill during dispatch")
    ) no_kill_during_dispatch (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(kill_valid && dispatch_valid))
    );

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
        commit_killed_out   = killing | killed[commit_id];
        commit_excepted_out = excepted[commit_id];
    end

    always_comb begin
        exception_pending_next = exception_pending;
        if (commit_excepted_out && commit_valid) exception_pending_next = 1'b0;
        if (except_valid) exception_pending_next = 1'b1;
    end

    RXVAssert #(
        .message("no dispatch during full commit buffer")
    ) no_dispatch_during_full (
        .clk      (clk),
        .en       (full),
        .condition(!dispatch_valid)
    );

    RXVAssert #(
        .message("no commit during empty commit buffer")
    ) no_commit_during_empty (
        .clk      (clk),
        .en       (empty),
        .condition(!commit_valid)
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
        .width(num_entries)
    ) killed_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (killed_next),
        .q    (killed)
    );

    RXVDFF #(
        .width(num_entries)
    ) excepted_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (excepted_next),
        .q    (excepted)
    );

    RXVDFF killing_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (killing_next),
        .q    (killing)
    );

    RXVDFF exception_pending_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exception_pending_next),
        .q    (exception_pending)
    );

endmodule
