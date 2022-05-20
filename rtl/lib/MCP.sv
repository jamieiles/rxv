`include "RXV.svh"
module MCP #(
    parameter width = 8,
    parameter reset_val = 8'b0
) (
    input  logic             reset,
    input  logic             clk_a,
    output logic             a_ready,
    input  logic             a_send,
    input  logic [width-1:0] a_datain,
    input  logic             clk_b,
    output logic [width-1:0] b_data,
    output logic             b_load
);

    logic                           a_en;
    logic                           a_ack;
    logic                           tx_busy;
    logic                           b_ack;
    logic                           tx_busy_next;

    wire a_load = a_send & a_ready;
    wire a_en_next = a_en ^ a_load;

    assign a_ready = a_ack | ~tx_busy;

    always_comb begin
        tx_busy_next = tx_busy;
        if (a_ack) begin
            tx_busy_next = 1'b0;
        end
        if (a_send) begin
            tx_busy_next = 1'b1;
        end
    end

    SyncPulse BLoadPulse (
        .clk  (clk_b),
        .reset(1'b0),
        .d    (a_en),
        .p    (b_load),
        .q    (b_ack)
    );

    SyncPulse AAckPulse (
        .clk  (clk_a),
        .reset(1'b0),
        .d    (b_ack),
        .p    (a_ack),
        // verilator lint_off PINCONNECTEMPTY
        .q    ()
        // verilator lint_on PINCONNECTEMPTY
    );

    RXVDFF a_en_next_reg (
        .clk  (clk_a),
        .reset(reset),
        .en   (1'b1),
        .d    (a_en_next),
        .q    (a_en)
    );

    RXVDFF tx_busy_reg (
        .clk  (clk_a),
        .reset(reset),
        .en   (1'b1),
        .d    (tx_busy_next),
        .q    (tx_busy)
    );

    RXVDFF #(
        .width(width),
        .reset_val(reset_val)
    ) tx_sample_reg (
        .clk  (clk_a),
        .reset(reset),
        .en   (a_load),
        .d    (a_datain),
        .q    (b_data)
    );

endmodule
