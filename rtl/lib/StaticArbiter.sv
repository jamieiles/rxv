`include "RXV.svh"
/*
 * Static priority arbiter with N requests/grants.  LSB in the request takes
 * priority over MSB.
 *
 * @grant is a combinational output and will be generated in the same cycle
 * as requests.
 */
module StaticArbiter #(
    parameter integer width = 4
) (
    input  logic             clk,
    input  logic             reset,
    input  logic [width-1:0] request,
    input  logic             hold,
    output logic [width-1:0] grant
);

    logic [width-1:0] grant_reg;
    logic [width-1:0] grant_reg_next;

    always_comb begin
        grant_reg_next = hold ? grant_reg : width'('b0);

        for (integer i = width - 1; i >= 0; --i) begin
            if (request[i] && !hold) grant_reg_next = width'(1'b1) << i;
        end
    end

    always_comb begin
        grant = grant_reg_next;
    end

    RXVDFF #(
        .width(width)
    ) grant_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (grant_reg_next),
        .q    (grant_reg)
    );

endmodule
