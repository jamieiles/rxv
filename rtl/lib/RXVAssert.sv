`default_nettype none

module RXVAssert #(
    parameter string message = "FAIL"
) (
    input logic clk,
    input logic en,
    input logic condition
);

`ifdef verilator
    always_ff @(posedge clk) begin
        if (en) begin
            if (!condition) begin
                $display("RXV: assertion failed: %m: %s", message);
                assert (1'b0);
            end
        end
    end
`endif  // verilator

endmodule
