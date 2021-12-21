`default_nettype none

module RXVAssert #(
    parameter logic [8*255-1:0] message = "FAIL"
) (
    input logic clk,
    input logic en,
    input logic condition
);

`ifdef verilator
    always_ff @(posedge clk) begin
        if (en) begin
            if (!condition) begin
                $display("%t RXV: assertion failed: %m: %-s", $time, message);
                assert (1'b0);
            end
        end
    end
`endif  // verilator

endmodule
