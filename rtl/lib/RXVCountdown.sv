`default_nettype none

module RXVCountdown #(
    parameter int               width      = 2,
    parameter logic [width-1:0] reload_val
) (
    input  logic clk,
    input  logic reset,
    input  logic reload,
    output logic expired
);

    logic [width-1:0] counter;
    logic [width-1:0] counter_next;

    always_comb begin
        counter_next = counter;

        if (reload) counter_next = reload_val;
        else if (|counter) counter_next = counter - 1'b1;

        expired = ~|counter;
    end

    RXVDFF #(
        .width($bits(counter))
    ) counter_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (counter_next),
        .q    (counter)
    );

endmodule
