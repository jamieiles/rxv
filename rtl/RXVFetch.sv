`default_nettype none
import RXVTypes::rxv_prediction;

module RXVFetch #(
    parameter logic [31:0] reset_address = 32'h80000000
) (
    input  logic                 clk,
    input  logic                 reset,
    input  logic                 except_valid,
    input  logic                 exception_pending,
    // To instruction cache
    output logic          [31:2] icache_address,
    output logic                 icache_valid,
    input  logic                 icache_busy,
    input  logic          [31:0] icache_instr,
    // To branch predictor
    output logic          [31:2] branch_predict_address,
    input  rxv_prediction        prediction,
    // Decode resteer
    input  logic                 decode_resteer,
    input  logic          [31:2] decode_resteer_tgt,
    // Decode stall
    input  logic                 decode_stall,
    input  logic          [31:2] decode_resume_tgt,
    // To decode
    output logic                 decode_valid,
    output logic          [31:2] decode_pc,
    output logic          [31:2] decode_next_pc,
    output logic          [31:0] decode_instr,
    output rxv_prediction        decode_prediction,
    // Exec branch resolution
    input  logic                 exec_resteer,
    input  logic          [31:2] exec_resteer_tgt,
    // Exception
    input  logic                 exception_resteer,
    input  logic          [31:2] exception_resteer_tgt
);

    /*
     * icache_address is a registered output from a variety of sources,
     * when not stalling icache_valid is high, the fetched address is passed to
     * the next stage and the PC updated.
     *
     * On the next cycle we get an instruction back if !icache_busy, otherwise
     * we need to resteer the fetch address to retry the fetch until !busy.
     * Once !busy we can take pc+4 and the fetched address and write them to the
     * decode stage along with valid+instruction data and prediction state.
     *
     * Splitting the PC generation and cache lookup into separate stages adds
     * an additional cycle on branch mispredict but increases Fmax by ~40%.
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
    logic        icache_valid_next;
    logic        icache_busy_start;
    logic        fetched_next;
    logic        resteer_pending;
    logic        resteer_pending_next;
    logic [31:2] resteer_target;
    logic [31:2] resteer_target_next;

    PosedgeDetect ICacheBusyStart (
        .clk  (clk),
        .reset(reset),
        .d    (icache_busy),
        .q    (icache_busy_start)
    );

    always_comb begin
        fetched_next = icache_valid & ~icache_busy & ~resteer & ~decode_stall &
            ~exception_pending & ~except_valid & ~(resteer_pending & icache_busy);
    end

    always_comb begin
        stalling = decode_stall | icache_busy;
    end

    always_comb begin
        decode_valid_next = fetched & ~stalling & ~resteer & ~resteer_pending & ~exception_pending & ~except_valid;
    end

    always_comb begin
        resteer = exception_resteer | exec_resteer | decode_resteer;
    end

    always_comb begin
        branch_predict_address = next_pc;
    end

    always_comb begin
        icache_valid_next = ~decode_stall & ~exception_pending & ~except_valid;
    end

    always_comb begin
        next_seq_pc = pc + 1'b1;
        next_pc     = !icache_busy && icache_valid ? next_seq_pc : pc;

        if (icache_busy_start) next_pc = fetched_pc;
        if (prediction.predicted && prediction.predict_taken) next_pc = prediction.prediction;
        if (decode_stall) next_pc = decode_resume_tgt;
        if (resteer_pending && icache_busy) next_pc = resteer_target;
        if (decode_resteer) next_pc = decode_resteer_tgt;
        if (exec_resteer) next_pc = exec_resteer_tgt;
        if (exception_resteer) next_pc = exception_resteer_tgt;
    end

    always_comb begin
        resteer_target_next = resteer_target;
        if (decode_stall) resteer_target_next = decode_resume_tgt;
        if (decode_resteer) resteer_target_next = decode_resteer_tgt;
        if (exec_resteer) resteer_target_next = exec_resteer_tgt;
        if (exception_resteer) resteer_target_next = exception_resteer_tgt;
    end

    always_comb begin
        resteer_pending_next = resteer_pending;
        if (~icache_busy) resteer_pending_next = 1'b0;
        if (resteer) resteer_pending_next = 1'b1;
        if (decode_stall) resteer_pending_next = 1'b1;
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
        .d    (icache_valid_next),
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

    RXVDFF resteer_pending_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (resteer_pending_next),
        .q    (resteer_pending)
    );

    RXVDFF #(
        .width(30)
    ) resteer_target_dff (
        .clk  (clk),
        .reset(reset),
        .en   (resteer | decode_stall),
        .d    (resteer_target_next),
        .q    (resteer_target)
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

    RXVDFFPipe #(
        .width ($bits(RXVTypes::rxv_prediction)),
        .stages(2)
    ) decode_prediction_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (prediction),
        .q    (decode_prediction)
    );

    RXVDFF fetched_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fetched_next),
        .q    (fetched)
    );

endmodule
