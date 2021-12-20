`default_nettype none

import RXVTypes::int_latency;
import RXVTypes::lsu_latency;

module RXVScheduler (
    input  logic clk,
    input  logic reset,
    input  logic dispatch_int,
    input  logic dispatch_lsu,
    input  logic global_stall_start,
    input  logic global_stall_end,
    output logic int_ready,
    output logic lsu_ready,
    output logic global_stall_active
);

    logic [lsu_latency:0] commit_schedule;
    logic [lsu_latency:0] commit_schedule_next;
    logic                 global_stall_next;
    logic                 global_stall;

    always_comb begin
        global_stall_active = global_stall;
    end

    always_comb begin
        global_stall_next = global_stall;
        if (global_stall_end) global_stall_next = 1'b0;
        if (global_stall_start) global_stall_next = 1'b1;
    end

    always_comb begin
        commit_schedule_next = {1'b0, commit_schedule[lsu_latency:1]};
        if (dispatch_int) commit_schedule_next[int_latency-1] = 1'b1;
        if (dispatch_lsu) commit_schedule_next[lsu_latency-1] = 1'b1;
    end

    always_comb begin
        int_ready = ~commit_schedule[int_latency] & ~global_stall;
        lsu_ready = ~commit_schedule[lsu_latency] & ~global_stall;
    end

`ifdef verilator
    always_ff @(posedge clk) begin
        if (dispatch_int) assert (!commit_schedule[int_latency]);
        if (dispatch_lsu) assert (!commit_schedule[lsu_latency]);
        assert (!(dispatch_int && dispatch_lsu));
    end
`endif

    RXVDFF #(
        .width($bits(commit_schedule))
    ) commit_schedule_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (commit_schedule_next),
        .q    (commit_schedule)
    );

    RXVDFF global_stall_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (global_stall_next),
        .q    (global_stall)
    );

endmodule
