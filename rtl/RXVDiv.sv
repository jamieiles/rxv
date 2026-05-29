// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

module RXVDiv (
    input  logic        clk,
    input  logic        reset,
    input  logic        valid,
    input  logic        is_signed,
    input  logic [31:0] dividend,
    input  logic [31:0] divisor,
    output logic [31:0] quotient,
    output logic [31:0] remainder
);

    logic [63:0] D;
    logic [63:0] D_next;
    logic [64:0] R;
    logic [64:0] R_next;

    logic [31:0] divisor_magnitude;
    logic [31:0] dividend_magnitude;

    logic        signs_equal_next;
    logic        signs_equal;
    logic        dividend_negative_next;
    logic        dividend_negative;
    logic        signed_div_next;
    logic        signed_div;
    logic [ 4:0] idx;
    logic [ 4:0] idx_next;
    logic [31:0] quotient_next;

    always_comb begin
        idx_next = idx;
        if (valid) idx_next = 5'd31;
        else if (|idx) idx_next = idx - 1'b1;
    end

    always_comb begin
        divisor_magnitude      = (divisor + {32{divisor[31]}}) ^ {32{divisor[31]}};
        dividend_magnitude     = (dividend + {32{dividend[31]}}) ^ {32{dividend[31]}};
        signs_equal_next       = signs_equal;
        D_next                 = D;
        R_next                 = R;
        quotient_next          = quotient;
        dividend_negative_next = dividend_negative;
        signed_div_next        = signed_div;

        if (valid) begin
            if (is_signed) begin
                R_next = {33'b0, dividend_magnitude};
                D_next = {divisor_magnitude, 32'b0};
            end else begin
                R_next = {33'b0, dividend};
                D_next = {divisor, 32'b0};
            end

            quotient_next          = 32'b0;
            signs_equal_next       = dividend[31] == divisor[31];
            dividend_negative_next = $signed(dividend) < 0;
            signed_div_next        = is_signed;
        end else begin
            if ($signed(R) >= 0) begin
                quotient_next[idx] = 1'b1;
                R_next             = (R * 2) - D;
            end else begin
                quotient_next[idx] = 1'b0;
                R_next             = (R * 2) + D;
            end

            if (~|idx) begin
                quotient_next = quotient_next - ~quotient_next;

                if ($signed(R_next) < 0 && ~&quotient_next) begin
                    quotient_next = quotient_next - 1'b1;
                    R_next        = R_next + $signed(D);
                end

                if (signed_div && ~&quotient_next) begin
                    if (!signs_equal) quotient_next = ~quotient_next + 1'b1;
                end
                if (signed_div && dividend_negative) R_next[63:32] = ~R_next[63:32] + 1'b1;

            end
        end
        remainder = R[63:32];
    end

    RXVAssert no_div_while_busy (
        .clk      (clk),
        .en       (|idx),
        .condition(!valid)
    );

    RXVDFF #(
        .width($bits(idx))
    ) idx_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (idx_next),
        .q    (idx)
    );

    RXVDFF #(
        .width(64)
    ) D_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (D_next),
        .q    (D)
    );

    RXVDFF #(
        .width(65)
    ) R_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (R_next),
        .q    (R)
    );

    RXVDFF #(
        .width(32)
    ) quotient_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (quotient_next),
        .q    (quotient)
    );

    RXVDFF signs_equal_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (signs_equal_next),
        .q    (signs_equal)
    );

    RXVDFF dividend_negative_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dividend_negative_next),
        .q    (dividend_negative)
    );

    RXVDFF signed_div_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (signed_div_next),
        .q    (signed_div)
    );

endmodule
