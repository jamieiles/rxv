`default_nettype none

import RXVTypes::int_latency;
import RXVTypes::lsu_latency;
import RXVTypes::mul_latency;
import RXVTypes::div_latency;

module RXVScheduler (
    input  logic clk,
    input  logic reset,
    input  logic schedule_int,
    input  logic schedule_lsu,
    input  logic schedule_mul,
    input  logic schedule_div,
    input  logic global_stall_start,
    input  logic global_stall_end,
    output logic int_ready,
    output logic lsu_ready,
    output logic mul_ready,
    output logic div_ready,
    output logic global_stall_active
);

    logic [div_latency:0] commit_schedule;
    logic [div_latency:0] commit_schedule_next;
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
        commit_schedule_next = {1'b0, commit_schedule[div_latency:1]};
        if (schedule_int) commit_schedule_next[int_latency-1] = 1'b1;
        if (schedule_lsu) commit_schedule_next[lsu_latency-1] = 1'b1;
        if (schedule_mul) commit_schedule_next[mul_latency-1] = 1'b1;
        if (schedule_div) commit_schedule_next[div_latency-1] = 1'b1;
    end

    always_comb begin
        int_ready = ~commit_schedule[int_latency] & ~global_stall;
        lsu_ready = ~commit_schedule[lsu_latency] & ~global_stall;
        mul_ready = ~commit_schedule[mul_latency] & ~global_stall;
        div_ready = ~commit_schedule[div_latency] & ~global_stall;
    end

    RXVAssert schedule_int_idle (
        .clk      (clk),
        .en       (schedule_int),
        .condition(!commit_schedule[int_latency])
    );

    RXVAssert schedule_lsu_idle (
        .clk      (clk),
        .en       (schedule_lsu),
        .condition(!commit_schedule[lsu_latency])
    );

    RXVAssert schedule_mul_idle (
        .clk      (clk),
        .en       (schedule_mul),
        .condition(!commit_schedule[mul_latency])
    );

    RXVAssert schedule_div_idle (
        .clk      (clk),
        .en       (schedule_div),
        .condition(!commit_schedule[div_latency])
    );

    RXVAssert no_simultaneous_dispatch (
        .clk      (clk),
        .en       (1'b1),
        .condition(3'(schedule_lsu) + 3'(schedule_int) + 3'(schedule_mul) + 3'(schedule_div) <= 1)
    );

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
