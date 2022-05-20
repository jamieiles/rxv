`include "RXV.svh"

import RXVTypes::rxv_prediction;

module RXVBranchPredictorWrapper #(
    parameter int num_entries = 256,
    parameter int tag_bits    = 20
) (
    input  logic        clk,
    input  logic        reset,
    // Fetch port
    input  logic [31:2] fetch_address,
    output logic        fetch_prediction_valid,
    output logic [31:2] fetch_prediction,
    output logic        fetch_predict_taken,
    output logic [ 1:0] fetch_predict_strength,
    // Decode resteer, for false positive branch identification
    input  logic        decode_predict_kill,
    input  logic [31:2] decode_kill_address,
    // Exec resteer on branch resolution
    input  logic        exec_predict_update,
    input  logic [ 1:0] exec_predict_prev_strength,
    input  logic        exec_predict_taken,
    input  logic [31:2] exec_predict_address,
    input  logic [31:2] exec_predict_target
);

    rxv_prediction prediction;

    assign fetch_prediction_valid = prediction.predicted;
    assign fetch_prediction       = prediction.prediction;
    assign fetch_predict_taken    = prediction.predict_taken;
    assign fetch_predict_strength = prediction.predict_strength;

    RXVBranchPredictor #(
        .num_entries(num_entries),
        .tag_bits   (tag_bits)
    ) RXVBranchPredictor (
        .*
    );

endmodule
