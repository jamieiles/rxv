`include "RXV.svh"

import RXVTypes::rxv_pmu_evt;
import RXVTypes::pmu_evt_sel;

module RXVEventCounter (
    input  logic              clk,
    input  logic              reset,
    input  pmu_evt_bus        event_bus,
    input  pmu_evt_sel        sel,
    input  logic              inhibit,
    input  logic              m_mode,
    input  logic              m_inhibit,
    input  logic              s_mode,
    input  logic              s_inhibit,
    input  logic              u_mode,
    input  logic              u_inhibit,
    input  logic              count_wren,
    input  logic              counth_wren,
    input  logic       [31:0] count_wrval,
    output logic       [63:0] count,
    output logic              overflow
);

    logic [63:0] count_next;
    logic        incr;
    logic        update;

    always_comb begin
        logic evt_pulse;
        logic filter;

        evt_pulse = event_bus[sel];
        filter    = ((m_mode & ~m_inhibit) | (s_mode & ~s_inhibit) | (u_mode & ~u_inhibit));
        incr      = evt_pulse & filter & ~inhibit;
        update    = incr | count_wren | counth_wren;
    end

    always_comb begin
        count_next = count;
        if (count_wren) count_next[31:0] = count_wrval;
        else if (counth_wren) count_next[63:32] = count_wrval;
        else count_next = count + 1'b1;
        overflow = ~count_wren & ~counth_wren & &count & incr;
    end

    RXVDFF #(
        .width(64)
    ) count_dff (
        .clk  (clk),
        .reset(reset),
        .en   (update),
        .d    (count_next),
        .q    (count)
    );

endmodule
