`default_nettype none
module BitSync (
    input  logic clk,
    input  logic reset,
    input  logic d,
    output logic q
);

    logic p1;
    logic p2;

    DFF p1_dff (
        .clk(clk),
        .reset(reset),
        .en(1'b1),
        .d(d),
        .q(p1)
    );

    DFF p2_dff (
        .clk(clk),
        .reset(reset),
        .en(1'b1),
        .d(p1),
        .q(q)
    );

endmodule
