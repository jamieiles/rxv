`include "RXV.svh"
module RXVDFFPipe #(
    parameter width     = 1,
    parameter reset_val = 0,
    parameter stages    = 1
) (
    input  logic             clk,
    input  logic             reset,
    input  logic             en,
    input  logic [width-1:0] d,
    output logic [width-1:0] q
);

    logic [width-1:0] stage_reg[0:stages-1];

    assign q = stage_reg[stages-1];

    genvar i;
    generate
        RXVDFF #(
            .width    (width),
            .reset_val(reset_val)
        ) stage0 (
            .clk  (clk),
            .reset(reset),
            .en   (en),
            .d    (d),
            .q    (stage_reg[0])
        );

        for (i = 1; i < stages; i = i + 1) begin : stageI
            RXVDFF #(
                .width    (width),
                .reset_val(reset_val)
            ) stageI (
                .clk  (clk),
                .reset(reset),
                .en   (en),
                .d    (stage_reg[i-1]),
                .q    (stage_reg[i])
            );
        end
    endgenerate

endmodule
