// Copyright 2026 Jamie Iles
// SPDX-License-Identifier: Apache-2.0
`include "RXV.svh"

import RXVTypes::rxv_prediction;

module RXVBranchPredictor #(
    parameter int num_entries = 256,
    parameter int tag_bits    = 20
) (
    `POWER_PIN_PORTS
    input  logic                 clk,
    input  logic                 reset,
    // Fetch port
    input  logic          [31:2] fetch_address,
    output rxv_prediction        prediction,
    // Decode resteer, for false positive branch identification
    input  logic                 decode_predict_kill,
    input  logic          [31:2] decode_kill_address,
    // Exec resteer on branch resolution
    input  logic                 exec_predict_update,
    input  logic          [ 1:0] exec_predict_prev_strength,
    input  logic                 exec_predict_taken,
    input  logic          [31:2] exec_predict_address,
    input  logic          [31:2] exec_predict_target
);

    localparam btb_width = tag_bits + $bits(prediction.prediction) + 2 + 1;
    localparam index_bits = $clog2(num_entries);

    // verilator lint_off UNUSED
    function logic [index_bits-1:0] addr_index;
        input logic [31:2] addr;
        addr_index = addr[2+:index_bits];
    endfunction

    function logic [tag_bits-1:0] addr_tag;
        input logic [31:2] addr;
        addr_tag = addr[2+index_bits+:tag_bits];
    endfunction
    // verilator lint_on UNUSED

    function logic [1:0] strength;
        input logic [1:0] prev_strength;
        input logic taken;

        begin
            unique case ({
                prev_strength, taken
            })
                3'b00_0: strength = 2'b11;
                3'b00_1: strength = 2'b01;
                3'b01_0: strength = 2'b00;
                3'b01_1: strength = 2'b01;
                3'b10_0: strength = 2'b10;
                3'b10_1: strength = 2'b11;
                3'b11_0: strength = 2'b10;
                3'b11_1: strength = 2'b00;
                default: strength = 2'b00;
            endcase
        end
    endfunction

    logic [  tag_bits-1:0] btb_lookup_tag;
    logic [           1:0] btb_lookup_strength;
    logic                  btb_lookup_valid;
    logic [          31:2] last_fetch_address;
    logic [index_bits-1:0] update_addr;
    logic                  update;
    logic [  tag_bits-1:0] update_tag;
    logic [           1:0] update_strength;
    logic [          31:2] update_target;
    logic                  update_valid;
    logic [          31:2] predict_target;
    logic [index_bits-1:0] lookup_addr;

    DPRAM #(
        .depth(num_entries),
        .width(btb_width)
    ) BTB (
        .clk   (clk),
        .reset (reset),
        .addr_a(lookup_addr),
        .dout_a({btb_lookup_tag, btb_lookup_strength, predict_target, btb_lookup_valid}),
        .addr_b(update_addr),
        .wren_b(update),
        .din_b ({update_tag, update_strength, update_target, update_valid})
    );

    always_comb begin
        lookup_addr = addr_index(fetch_address);
    end

    always_comb begin
        prediction.predicted = btb_lookup_tag == addr_tag(last_fetch_address) && btb_lookup_valid;
        // Misses return a weakly not-taken in case they are later resolved to be
        // a taken branch so will be updated to be weakly taken, otherwise it will
        // be entered as strongly not taken.
        prediction.predict_strength = prediction.predicted ? btb_lookup_strength : 2'b11;
        prediction.predict_taken = $signed(prediction.predict_strength) >= $signed(2'b00);
        prediction.prediction = predict_target;
    end

    // Exec updates take priority over decode, when killing a prediction at decode
    // because there is no associativity we just need to set it to be strongly
    // not take, the tag and target do not matter as they won't be used in a
    // prediction.
    always_comb begin
        update = decode_predict_kill | exec_predict_update;
        update_addr = exec_predict_update ? addr_index(exec_predict_address) :
            addr_index(decode_kill_address);
        update_strength = exec_predict_update ?
            strength(exec_predict_prev_strength, exec_predict_taken) : 2'b10;
        update_tag = exec_predict_update ? addr_tag(exec_predict_address) : tag_bits'('b0);
        update_valid = exec_predict_update;
        update_target = exec_predict_target;
    end

    RXVDFF #(
        .width(30)
    ) last_fetch_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fetch_address),
        .q    (last_fetch_address)
    );

endmodule
