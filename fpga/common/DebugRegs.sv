// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

// LEDs and seven segment displays for boot progress and panics, as the
// DE0-CV has no serial console:
//
//   0x0 [num_leds-1:0] LEDs
//   0x4 [4*num_digits-1:0] hex value, a nibble per digit
//   0x8 [num_digits-1:0] digit enables
//
// Segments are active low, segment 0 is a, 6 is g.
module DebugRegs #(
    parameter int num_leds   = 10,
    parameter int num_digits = 6
) (
    input  logic                      clk,
    input  logic                      reset,
    // Register interface (AXILiteRegs)
    // verilator lint_off UNUSEDSIGNAL
    input  logic                      reg_wr,
    input  logic [              15:0] reg_waddr,
    input  logic [              31:0] reg_wdata,
    input  logic [               3:0] reg_wstrb,
    input  logic                      reg_rd,
    input  logic [              15:0] reg_raddr,
    // verilator lint_on UNUSEDSIGNAL
    output logic [              31:0] reg_rdata,
    output logic [      num_leds-1:0] leds,
    output logic [7*num_digits-1:0]   hex_n
);

    logic [4*num_digits-1:0] value;
    logic [  num_digits-1:0] digit_en;

    function automatic logic [6:0] seg7(input logic [3:0] v);
        unique case (v)
            4'h0: seg7 = 7'b0111111;
            4'h1: seg7 = 7'b0000110;
            4'h2: seg7 = 7'b1011011;
            4'h3: seg7 = 7'b1001111;
            4'h4: seg7 = 7'b1100110;
            4'h5: seg7 = 7'b1101101;
            4'h6: seg7 = 7'b1111101;
            4'h7: seg7 = 7'b0000111;
            4'h8: seg7 = 7'b1111111;
            4'h9: seg7 = 7'b1101111;
            4'ha: seg7 = 7'b1110111;
            4'hb: seg7 = 7'b1111100;
            4'hc: seg7 = 7'b0111001;
            4'hd: seg7 = 7'b1011110;
            4'he: seg7 = 7'b1111001;
            default: seg7 = 7'b1110001;
        endcase
    endfunction

    always_comb begin
        for (int d = 0; d < num_digits; ++d)
            hex_n[d*7+:7] = digit_en[d] ? ~seg7(value[d*4+:4]) : 7'h7f;

        unique case (reg_raddr[3:2])
            2'd0:    reg_rdata = 32'(leds);
            2'd1:    reg_rdata = 32'(value);
            2'd2:    reg_rdata = 32'(digit_en);
            default: reg_rdata = '0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (reg_wr) begin
            unique case (reg_waddr[3:2])
                2'd0:    leds <= reg_wdata[num_leds-1:0];
                2'd1:    value <= reg_wdata[4*num_digits-1:0];
                2'd2:    digit_en <= reg_wdata[num_digits-1:0];
                default: ;
            endcase
        end

        if (reset) begin
            leds     <= '0;
            value    <= '0;
            digit_en <= '0;
        end
    end

endmodule
