// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVTypes::pmu_evt_bus;
import RXVTypes::pmu_evt_sel;

module RXVPMU #(
    parameter int num_event_counters = 8
) (
    input logic                                clk,
    input logic                                reset,
    input logic                                retire_valid,
    input logic                                cyclesh_wren,
    input logic                                cyclesl_wren,
    input logic                                cycles_inhibit,
    input logic                                instreth_wren,
    input logic                                instretl_wren,
    input logic                                instret_inhibit,
    input logic [31:0]                         csr_wrval,
    input pmu_evt_bus                          pmu_events,
    input pmu_evt_sel [num_event_counters-1:0] pmu_event_sel,
    input logic [num_event_counters-1:0]       pmu_event_inhibit,
    input logic                                m_mode,
    input logic [num_event_counters-1:0]       pmu_m_inhibit,
    input logic                                s_mode,
    input logic [num_event_counters-1:0]       pmu_s_inhibit,
    input logic                                u_mode,
    input logic [num_event_counters-1:0]       pmu_u_inhibit,
    input logic [num_event_counters-1:0]       pmu_count_wren,
    input logic [num_event_counters-1:0]       pmu_counth_wren,
    input logic [31:0]                         pmu_count_wrval,
    output logic [63:0]                        pmu_count[num_event_counters],
    output logic [num_event_counters-1:0]      pmu_overflow,
    // verilog_format: off
    output logic [63:0]                        pmu_cycles  /* verilator public */,
    output logic [63:0]                        pmu_instret /* verilator public */
    // verilog_format: on
);

    // The events come straight from execute (e.g. the branch compare) so
    // register them, along with the mode they occurred in, before the
    // counters to keep the counter enables and overflow off the critical
    // path.  The programmable counters lag by a cycle, mcycle and minstret
    // are counted directly.
    pmu_evt_bus pmu_events_q;
    logic       m_mode_q;
    logic       s_mode_q;
    logic       u_mode_q;

    RXVDFF #(
        .width($bits(pmu_evt_bus) + 3)
    ) pmu_events_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    ({pmu_events, m_mode, s_mode, u_mode}),
        .q    ({pmu_events_q, m_mode_q, s_mode_q, u_mode_q})
    );

    genvar i;
    generate
        for (i = 0; i < num_event_counters; ++i) begin : evt_counter
            RXVEventCounter counter (
                .clk        (clk),
                .reset      (reset),
                .event_bus  (pmu_events_q),
                .sel        (pmu_event_sel[i]),
                .inhibit    (pmu_event_inhibit[i]),
                .m_mode     (m_mode_q),
                .m_inhibit  (pmu_m_inhibit[i]),
                .s_mode     (s_mode_q),
                .s_inhibit  (pmu_s_inhibit[i]),
                .u_mode     (u_mode_q),
                .u_inhibit  (pmu_u_inhibit[i]),
                .count_wren (pmu_count_wren[i]),
                .counth_wren(pmu_counth_wren[i]),
                .count_wrval(pmu_count_wrval),
                .count      (pmu_count[i]),
                .overflow   (pmu_overflow[i])
            );
        end
    endgenerate

    logic [63:0] pmu_cycles_next;
    logic [63:0] pmu_instret_next;
    logic        pmu_instret_update;
    logic        suppress_instret_update_next;
    logic        suppress_instret_update;

    always_comb begin
        pmu_cycles_next = pmu_cycles;
        if (!cycles_inhibit) pmu_cycles_next = pmu_cycles + 1'b1;
        if (cyclesh_wren) pmu_cycles_next = {csr_wrval, pmu_cycles[31:0]};
        if (cyclesl_wren) pmu_cycles_next = {pmu_cycles[63:32], csr_wrval};
    end

    always_comb begin
        pmu_instret_next = pmu_instret;
        if (!instret_inhibit) pmu_instret_next = pmu_instret + 1'b1;
        if (instreth_wren) pmu_instret_next = {csr_wrval, pmu_instret[31:0]};
        if (instretl_wren) pmu_instret_next = {pmu_instret[63:32], csr_wrval};

        pmu_instret_update = instreth_wren | instretl_wren | (retire_valid & ~suppress_instret_update);
        suppress_instret_update_next = instreth_wren | instretl_wren;
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

    RXVDFF suppress_instret_update_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (suppress_instret_update_next),
        .q    (suppress_instret_update)
    );

endmodule
