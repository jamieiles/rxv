`default_nettype none
import RXVTypes::rxv_prediction;

module RXVFetchWrapper #(
    parameter logic [31:0] reset_address = 32'h80000000
) (
    input  logic        clk,
    input  logic        reset,
    // To instruction cache
    output logic [31:2] icache_address,
    output logic        icache_valid,
    input  logic        icache_busy,
    input  logic [31:0] icache_instr,
    // To branch predictor
    output logic [31:2] branch_predict_address,
    input  logic        branch_predict_valid,
    input  logic [31:2] branch_prediction,
    input  logic        branch_predict_taken,
    input  logic [ 1:0] branch_predict_strength,
    // Decode resteer
    input  logic        decode_resteer,
    input  logic [31:2] decode_resteer_tgt,
    // Decode stall
    input  logic        decode_stall,
    input  logic [31:2] decode_resume_tgt,
    // To decode
    output logic        decode_valid,
    output logic [31:2] decode_pc,
    output logic [31:2] decode_next_pc,
    output logic [31:0] decode_instr,
    output logic        decode_predicted,
    output logic        decode_predict_taken,
    output logic [ 1:0] decode_predict_strength,
    output logic [31:2] decode_prediction,
    // Exec branch resolution
    input  logic        exec_resteer,
    input  logic [31:2] exec_resteer_tgt
);

    rxv_prediction predict_in;
    rxv_prediction predict_out;

    assign predict_in.predicted        = branch_predict_valid;
    assign predict_in.prediction       = branch_prediction;
    assign predict_in.predict_taken    = branch_predict_taken;
    assign predict_in.predict_strength = branch_predict_strength;

    assign decode_predicted            = predict_out.predicted;
    assign decode_predict_taken        = predict_out.predict_taken;
    assign decode_predict_strength     = predict_out.predict_strength;
    assign decode_prediction           = predict_out.prediction;

    RXVFetch #(
        .reset_address(reset_address)
    ) RXVFetch (
        .prediction       (predict_in),
        .decode_prediction(predict_out),
        .*
    );

endmodule
