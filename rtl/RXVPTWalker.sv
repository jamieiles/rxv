// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVMMU::sv32_pte_t;
import RXVMMU::pmp_perms;

module RXVPTWalker (
    input  logic              clk,
    input  logic              reset,
    input  logic      [31:12] va,
    input  logic              valid,
    input  logic      [31:12] translation_base,
    output logic              busy,
    output sv32_pte_t         pte_out,
    output logic              is_megapage,
    output logic              translation_error,
    output logic              pmp_violation,
    output logic      [ 31:2] dcache_address,
    output logic              dcache_valid,
    input  logic              dcache_busy,
    input  logic      [ 31:0] dcache_rdata,
    output logic      [ 31:2] dcache_phys_in,
    output logic              dcache_phys_valid,
    input  logic              dcache_grant,
    output logic      [ 31:2] pmp_addr,
    // verilator lint_off UNUSED
    input  pmp_perms          pmp
    // verilator lint_on UNUSED
);

    localparam int dcache_latency = 2;

    typedef enum logic [1:0] {
        STATE_IDLE = 2'b00,
        STATE_LEVEL1 = 2'b01,
        STATE_LEVEL0 = 2'b11,
        STATE_WAIT_GRANT = 2'b10
    } ptwalk_state;

    logic        [                    9:0] vpn1;
    logic        [                    9:0] vpn0;
    sv32_pte_t                             pte_in;
    logic                                  dcache_latency_reload;
    logic                                  dcache_latency_expired;
    ptwalk_state                           state;
    ptwalk_state                           next_state;
    logic                                  dcache_valid_next;
    logic        [                   31:2] dcache_address_next;
    logic                                  busy_next;
    logic                                  is_megapage_next;
    logic                                  translation_error_next;
    logic                                  pmp_violation_next;
    logic                                  result_update;
    logic                                  dcache_phys_valid_next;
    logic        [$bits(ptwalk_state)-1:0] state_q;

    RXVCountdown #(
        .width     ($bits(dcache_latency)),
        .reload_val(dcache_latency)
    ) dcache_latency_count (
        .clk    (clk),
        .reset  (reset),
        .reload (dcache_latency_reload),
        .expired(dcache_latency_expired)
    );

    initial assert ($bits(sv32_pte_t) == 32);

    always_comb begin
        pte_in = sv32_pte_t'(dcache_rdata);
    end

    always_comb begin
        dcache_latency_reload = next_state != state;
    end

    always_comb begin
        case (state)
            STATE_IDLE:
            next_state = valid ? (dcache_grant ? STATE_LEVEL1 : STATE_WAIT_GRANT) : STATE_IDLE;
            STATE_WAIT_GRANT: next_state = dcache_grant ? STATE_LEVEL1 : STATE_WAIT_GRANT;
            STATE_LEVEL1:
            next_state = (dcache_grant && !pmp.read) ? STATE_IDLE :
                ~dcache_latency_expired || dcache_busy ? STATE_LEVEL1 :
                !pte_in.valid ? STATE_IDLE :
                pte_in.write && !pte_in.read ? STATE_IDLE :
                pte_in.read || pte_in.exec ? STATE_IDLE :
                STATE_LEVEL0;
            STATE_LEVEL0:
            next_state = (dcache_grant && !pmp.read) ? STATE_IDLE :
                ~dcache_latency_expired || dcache_busy ? STATE_LEVEL0 : STATE_IDLE;
            default: ;
        endcase
    end

    always_comb begin
        case (state)
            STATE_IDLE, STATE_WAIT_GRANT: begin
                dcache_address_next = {translation_base, vpn1};
                dcache_valid_next   = state == STATE_WAIT_GRANT ? 1'b1 : valid;
            end
            STATE_LEVEL1: begin
                dcache_address_next = ~dcache_latency_expired || dcache_busy ?
                    {translation_base, vpn1} : {pte_in.ppn1[9:0], pte_in.ppn0, vpn0};
                dcache_valid_next = next_state == STATE_LEVEL0;
            end
            STATE_LEVEL0: begin
                dcache_address_next = dcache_address;  //{pte_in.ppn1[9:0], pte_in.ppn0, vpn0};
                dcache_valid_next   = 1'b0;
            end
            default: begin
                dcache_address_next = 'b0;
                dcache_valid_next   = 1'b0;
            end
        endcase
    end

    always_comb begin
        pmp_addr = dcache_address;
    end

    always_comb begin
        busy_next = busy;
        if (state == STATE_IDLE) busy_next = valid;
        if (state == STATE_WAIT_GRANT) busy_next = 1'b1;
        if (state == STATE_LEVEL1 || state == STATE_LEVEL0) busy_next = next_state != STATE_IDLE;
    end

    always_comb begin
        unique case (state)
            // W without R is reserved at any level, a megapage must be
            // aligned and the last level must be a leaf.
            STATE_LEVEL1: begin
                translation_error_next = !pte_in.valid || (pte_in.write && !pte_in.read) ||
                    |pte_in.ppn0;
                pmp_violation_next     = dcache_grant && !pmp.read && !translation_error_next;
            end
            STATE_LEVEL0: begin
                translation_error_next = !pte_in.valid || (pte_in.write && !pte_in.read) ||
                    !(pte_in.read || pte_in.exec);
                pmp_violation_next     = dcache_grant && !pmp.read && !translation_error_next;
            end
            default: begin
                translation_error_next = 1'b0;
                pmp_violation_next     = 1'b0;
            end
        endcase
        is_megapage_next = state == STATE_LEVEL1 && next_state == STATE_IDLE;
    end

    always_comb begin
        result_update = (state == STATE_LEVEL1 || state == STATE_LEVEL0) && next_state == STATE_IDLE;
    end

    always_comb begin
        vpn1 = va[31:22];
        vpn0 = va[21:12];
    end

    always_comb begin
        dcache_phys_valid_next = (dcache_valid | dcache_busy) & pmp.read;
    end

    always_comb begin
        state = ptwalk_state'(state_q);
    end

    RXVDFF #(
        .width($bits(state))
    ) state_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_state),
        .q    (state_q)
    );

    RXVDFF dcache_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dcache_valid_next),
        .q    (dcache_valid)
    );

    RXVDFF #(
        .width($bits(dcache_address))
    ) dcache_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dcache_address_next),
        .q    (dcache_address)
    );

    RXVDFF busy_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (busy_next),
        .q    (busy)
    );

    RXVDFF #(
        .width(32)
    ) pte_out_dff (
        .clk  (clk),
        .reset(reset),
        .en   (result_update),
        .d    (pte_in),
        .q    (pte_out)
    );

    RXVDFF is_megapage_dff (
        .clk  (clk),
        .reset(reset),
        .en   (result_update),
        .d    (is_megapage_next),
        .q    (is_megapage)
    );

    RXVDFF translation_error_dff (
        .clk  (clk),
        .reset(reset),
        .en   (result_update),
        .d    (translation_error_next),
        .q    (translation_error)
    );

    RXVDFF pmp_violation_dff (
        .clk  (clk),
        .reset(reset),
        .en   (result_update),
        .d    (pmp_violation_next),
        .q    (pmp_violation)
    );

    RXVDFF #(
        .width(30)
    ) dcache_phys_in_dff (
        .clk  (clk),
        .reset(reset),
        .en   (dcache_valid),
        .d    (dcache_address),
        .q    (dcache_phys_in)
    );

    RXVDFF dcache_phys_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dcache_phys_valid_next),
        .q    (dcache_phys_valid)
    );

endmodule
