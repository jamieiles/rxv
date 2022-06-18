`include "RXV.svh"
module DPRAM #(
    parameter depth = 32,
    parameter width = 8
) (
    `POWER_PIN_PORTS
    input  logic                 clk,
    // verilator lint_off UNUSED
    input  logic                 reset,
    // verilator lint_on UNUSED
    // Port A
    input  logic [addr_bits-1:0] addr_a,
    output logic [    width-1:0] dout_a,
    // Port B
    input  logic [addr_bits-1:0] addr_b,
    input  logic                 wren_b,
    input  logic [    width-1:0] din_b
);

    localparam addr_bits = $clog2(depth);

    generate
        if (depth == 256 && width == 43) begin
            logic             read_en;
            logic [width-1:0] bypass_reg;
            logic [width-1:0] ram_a_out;
            logic             bypass_en;

            sram_dp_43_256_sky130 ram (
                `POWER_PIN_CONNECT
                // RW port
                .clk0 (clk),
                .csb0 (~wren_b),
                .web0 (~wren_b),
                .addr0(addr_b),
                .din0 (din_b),
                .dout0(),
                // Read port
                .clk1 (clk),
                .csb1 (read_en),
                .addr1(addr_a),
                .dout1(ram_a_out)
            );

            always_comb begin
                read_en = addr_a != addr_b;
                dout_a  = bypass_en ? bypass_reg : ram_a_out;
            end

            RXVDFF #(
                .width(width)
            ) bypass_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (din_b),
                .q    (bypass_reg)
            );

            RXVDFF bypass_en_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (~read_en),
                .q    (bypass_en)
            );
        end else if (depth == 128 && width == 8) begin
            logic             read_en;
            logic [width-1:0] bypass_reg;
            logic [width-1:0] ram_a_out;
            logic             bypass_en;

            sram_dp_8_128_sky130 ram (
                `POWER_PIN_CONNECT
                // RW port
                .clk0 (clk),
                .csb0 (~wren_b),
                .web0 (~wren_b),
                .addr0(addr_b),
                .din0 (din_b),
                .dout0(),
                // Read port
                .clk1 (clk),
                .csb1 (read_en),
                .addr1(addr_b),
                .dout1(ram_a_out)
            );

            always_comb begin
                read_en = addr_a != addr_b;
                dout_a  = bypass_en ? bypass_reg : ram_a_out;
            end

            RXVDFF #(
                .width(width)
            ) bypass_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (din_b),
                .q    (bypass_reg)
            );

            RXVDFF bypass_en_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (~read_en),
                .q    (bypass_en)
            );
        end else begin
            logic [width-1:0] mem[0:depth-1];

            always_ff @(posedge clk) begin
                if (wren_b) begin
                    mem[addr_b] <= din_b;
                end
            end

            always_ff @(posedge clk) begin
                dout_a <= mem[addr_a];
            end

            integer i;
            initial begin
                for (i = 0; i < depth; i = i + 1) mem[i] = width'(1'b0);
            end
        end
    endgenerate

endmodule
