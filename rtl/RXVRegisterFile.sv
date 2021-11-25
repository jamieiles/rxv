import RXVTypes::phys_reg_tag;
import RXVTypes::num_phys_regs;

module RXVRegisterFile (
    input  logic               clk,
    input  logic               reset,
    input  phys_reg_tag        rd_addr_a,
    output logic        [31:0] rd_data_a,
    input  phys_reg_tag        rd_addr_b,
    output logic        [31:0] rd_data_b,
    input  logic               wr_en,
    input  phys_reg_tag        wr_addr,
    input  logic        [31:0] wr_data
);

    logic [             31:0] reg_out          [0:num_phys_regs-1];
    logic [num_phys_regs-1:0] reg_wren_encoded;
    logic [num_phys_regs-1:0] reg_wren;

    logic [             31:0] data_a_next;
    logic [             31:0] data_b_next;

    OneHotEncode #(
        .width(num_phys_regs)
    ) reg_wren_decode (
        .d(wr_addr),
        .q(reg_wren_encoded)
    );

    generate
        genvar i;

        for (i = 0; i < num_phys_regs; i = i + 1) begin : gen_reg
            RXVDFF #(
                .width(32)
            ) reg_f (
                .clk  (clk),
                .reset(reset),
                .en   (reg_wren[i]),
                .d    (wr_data),
                .q    (reg_out[i])
            );
        end
    endgenerate

    always_comb begin
        reg_wren = {{(num_phys_regs - 1) {1'b1}}, 1'b0} & reg_wren_encoded;
    end

    always_comb begin
        data_a_next = wr_en && wr_addr == rd_addr_a && |rd_addr_a ? wr_data : reg_out[rd_addr_a];
        data_b_next = wr_en && wr_addr == rd_addr_b && |rd_addr_b ? wr_data : reg_out[rd_addr_b];
    end

    RXVDFF #(
        .width(32)
    ) data_a_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (data_a_next),
        .q    (rd_data_a)
    );
    RXVDFF #(
        .width(32)
    ) data_b_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (data_b_next),
        .q    (rd_data_b)
    );

endmodule
