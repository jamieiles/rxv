`default_nettype none
module SyncPulse (
    input  logic clk,
    input  logic reset,
    input  logic d,
    output logic p,
    output logic q
);

    logic synced;
    logic last_val;

    assign p = synced ^ last_val;
    assign q = last_val;

    DFF last_val_reg (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (synced),
        .q    (last_val)
    );

    BitSync BitSync (
        .clk  (clk),
        .reset(reset),
        .d    (d),
        .q    (synced)
    );

endmodule
