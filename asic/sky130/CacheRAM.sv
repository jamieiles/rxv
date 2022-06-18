`include "RXV.svh"
module CacheRAM #(
    parameter depth             = 32,
    parameter lane_width        = 32,
    parameter num_lanes         = 4,
    parameter read_during_write = 1
) (
    `POWER_PIN_PORTS
    input  logic                 clk,
    // verilator lint_off UNUSED
    input  logic                 reset,
    // verilator lint_on UNUSED
    input  logic [addr_bits-1:0] addr,
    input  logic [num_lanes-1:0] lane_wren,
    input  logic [data_bits-1:0] din,
    output logic [data_bits-1:0] dout
);

    localparam addr_bits = $clog2(depth);
    localparam data_bits = lane_width * num_lanes;

    genvar i;

    generate
        if (depth == 128 && lane_width == 1 && num_lanes == 8 && read_during_write == 1) begin
            logic [data_bits-1:0] ram_out;
            logic [data_bits-1:0] bypass_reg;
            logic                 bypass_en;

            sram_1rw_8_128_sky130 ram (
                `POWER_PIN_CONNECT
                .clk0      (clk),
                .csb0      (1'b0),
                .web0      (~|lane_wren),
                .wmask0    (lane_wren),
                .spare_wen0(1'b0),
                .addr0     (addr),
                .din0      (din),
                .dout0     (ram_out)
            );

            RXVDFF #(
                .width(data_bits)
            ) bypass_data_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (din),
                .q    (bypass_reg)
            );

            RXVDFF bypass_en_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (|lane_wren),
                .q    (bypass_en)
            );

            assign dout = bypass_en ? bypass_reg : ram_out;
        end else if (depth == 128 && lane_width == 21 && num_lanes == 8 && read_during_write == 1) begin
            logic [data_bits-1:0] ram_out;
            logic [data_bits-1:0] bypass_reg;
            logic                 bypass_en;

            sram_1rw_168_128_sky130 ram (
                `POWER_PIN_CONNECT
                .clk0      (clk),
                .csb0      (1'b0),
                .web0      (~|lane_wren),
                .wmask0    (lane_wren),
                .spare_wen0(1'b0),
                .addr0     (addr),
                .din0      (din),
                .dout0     (ram_out)
            );

            RXVDFF #(
                .width(data_bits)
            ) bypass_data_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (din),
                .q    (bypass_reg)
            );

            RXVDFF bypass_en_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (|lane_wren),
                .q    (bypass_en)
            );

            assign dout = bypass_en ? bypass_reg : ram_out;
        end else if (depth == 1024 && lane_width == 32 && num_lanes == 8 && read_during_write == 0) begin
            sram_1rw_256_1024_sky130 ram (
                `POWER_PIN_CONNECT
                .clk0      (clk),
                .csb0      (1'b0),
                .web0      (~|lane_wren),
                .wmask0    (lane_wren),
                .spare_wen0(1'b0),
                .addr0     (addr),
                .din0      (din),
                .dout0     (dout)
            );
        end else begin
            for (i = 0; i < num_lanes; ++i) begin : ram
                logic [lane_width-1:0] lane_ram_out;

                RAM #(
                    .depth(depth),
                    .width(lane_width)
                ) lane_ram (
                    `POWER_PIN_CONNECT
                    .clk (clk),
                    .addr(addr),
                    .wren(lane_wren[i]),
                    .din (din[(i*lane_width)+:lane_width]),
                    // .dout(dout[(i*lane_width)+:lane_width])
                    .dout(lane_ram_out)
                );

                if (read_during_write) begin
                    logic [lane_width-1:0] lane_bypass_data_reg;
                    logic                  lane_bypass;

                    RXVDFF #(
                        .width(lane_width)
                    ) lane_bypass_data_dff (
                        .clk  (clk),
                        .reset(reset),
                        .en   (1'b1),
                        .d    (din[i*lane_width+:lane_width]),
                        .q    (lane_bypass_data_reg)
                    );

                    RXVDFF lane_bypass_dff (
                        .clk  (clk),
                        .reset(reset),
                        .en   (1'b1),
                        .d    (lane_wren[i]),
                        .q    (lane_bypass)
                    );

                    assign dout[(i*lane_width)+:lane_width] = lane_bypass ? lane_bypass_data_reg : lane_ram_out;
                end else begin
                    assign dout[(i*lane_width)+:lane_width] = lane_ram_out;
                end
            end
        end
    endgenerate

endmodule
