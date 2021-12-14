`default_nettype none

import RXVTypes::int_latency;
import RXVTypes::lsu_latency;

module RXVScheduler (
    input  logic clk,
    input  logic reset,
    input  logic dispatch_int,
    input  logic dispatch_lsu,
    output logic int_ready,
    output logic lsu_ready
);

    logic [lsu_latency:0] commit_schedule;
    logic [lsu_latency:0] commit_schedule_next;

    always_comb begin
        commit_schedule_next = {1'b0, commit_schedule[lsu_latency:1]};
        if (dispatch_int) commit_schedule_next[int_latency-1] = 1'b1;
        if (dispatch_lsu) commit_schedule_next[lsu_latency-1] = 1'b1;
    end

    always_comb begin
        int_ready = ~commit_schedule[int_latency];
        lsu_ready = ~commit_schedule[lsu_latency];
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

endmodule
