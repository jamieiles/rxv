`default_nettype none

module RXVFetch #(
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
    // Exec branch resolution
    input  logic        exec_resteer,
    input  logic [31:2] exec_resteer_tgt
);

    /*
     * icache_address is a combinational output from a variety of sources,
     * when not stalling icache_valid is high, the fetched address is passed to
     * the next stage and the PC updated.
     *
     * On the next cycle we get an instruction back if !icache_busy, otherwise
     * we need to resteer the fetch address to retry the fetch until !busy.
     * Once !busy we can take pc+4 and the fetched address and write them to the
     * decode stage along with valid+instruction data and prediction state.
     */

    logic [31:2] pc;
    logic [31:2] next_pc;
    logic [31:2] fetched_pc;
    logic [31:2] next_seq_pc;
    logic [31:2] next_seq_pc_reg;
    logic        stalling;
    logic        fetched;
    logic        decode_valid_next;
    logic        resteer;
    logic        icache_busy_start;

    PosedgeDetect ICacheBusyStart (
        .clk  (clk),
        .reset(reset),
        .d    (icache_busy),
        .q    (icache_busy_start)
    );

    always_comb begin
        stalling = decode_stall | icache_busy;
    end

    always_comb begin
        decode_valid_next = fetched & ~stalling & ~resteer;
    end

    always_comb begin
        resteer = exec_resteer | decode_resteer;
    end

    always_comb begin
        branch_predict_address = next_pc;
    end

    always_comb begin
        next_seq_pc = pc + 1'b1;
        next_pc     = !stalling && icache_valid ? next_seq_pc : pc;

        if (icache_busy) next_pc = icache_address;
        if (icache_busy_start) next_pc = fetched_pc;
        if (branch_predict_valid && branch_predict_taken) next_pc = branch_prediction;
        if (decode_resteer) next_pc = decode_resteer_tgt;
        if (exec_resteer) next_pc = exec_resteer_tgt;
        if (decode_stall) next_pc = decode_resume_tgt;
    end

    RXVDFF #(
        .width    (30),
        .reset_val(reset_address[31:2])
    ) pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_pc),
        .q    (pc)
    );

    RXVDFF #(
        .width(30)
    ) icache_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_pc),
        .q    (icache_address)
    );

    RXVDFF icache_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (~decode_stall),
        .q    (icache_valid)
    );

    RXVDFF #(
        .width(30)
    ) fetched_pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (icache_address),
        .q    (fetched_pc)
    );

    RXVDFF decode_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (decode_valid_next),
        .q    (decode_valid)
    );

    RXVDFF #(
        .width(30)
    ) decode_pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (decode_valid_next),
        .d    (fetched_pc),
        .q    (decode_pc)
    );

    RXVDFF #(
        .width(30)
    ) next_seq_pc_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_seq_pc),
        .q    (next_seq_pc_reg)
    );

    RXVDFF #(
        .width(30)
    ) decode_next_pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (decode_valid_next),
        .d    (next_seq_pc_reg),
        .q    (decode_next_pc)
    );

    RXVDFF #(
        .width(32)
    ) decode_instr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (decode_valid_next),
        .d    (icache_instr),
        .q    (decode_instr)
    );

    RXVDFF decode_predicted_dff (
        .clk  (clk),
        .reset(reset),
        .en   (decode_valid_next),
        .d    (branch_predict_valid),
        .q    (decode_predicted)
    );

    RXVDFF decode_predict_taken_dff (
        .clk  (clk),
        .reset(reset),
        .en   (decode_valid_next),
        .d    (branch_predict_taken),
        .q    (decode_predict_taken)
    );

    RXVDFF #(
        .width(2)
    ) decode_predict_strength_dff (
        .clk  (clk),
        .reset(reset),
        .en   (decode_valid_next),
        .d    (branch_predict_strength),
        .q    (decode_predict_strength)
    );

    RXVDFF fetched_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (icache_valid & ~icache_busy & ~resteer),
        .q    (fetched)
    );

endmodule
