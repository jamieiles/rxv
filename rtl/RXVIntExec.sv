`default_nettype none

import RXVTypes::rxv_alu_op;

module RXVIntExec #(
    parameter int commit_order = 3
) (
    input  logic                           clk,
    input  logic                           reset,
    input  logic                           exec_valid,
    input  rxv_alu_op                      exec_alu_op,
    input  logic                           exec_have_writeback,
    input  phys_reg_tag                    exec_rd,
    input  logic        [commit_width-1:0] exec_id,
    input  logic        [            31:0] op1,
    input  logic        [            31:0] op2,
    output phys_reg_tag                    exec_reg_addr,
    output logic                           exec_reg_wr_en,
    output logic        [            31:0] exec_reg_wr_data,
    output logic                           exec_complete,
    output logic        [commit_width-1:0] exec_complete_id
);

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic [31:0] alu_q;
    logic        zero;

    RXVALU RXVALU (
        .a   (op1),
        .b   (op2),
        .op  (exec_alu_op),
        .q   (alu_q),
        .zero(zero)
    );

    RXVDFF #(
        .width($bits(phys_reg_tag))
    ) exec_reg_addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_rd),
        .q    (exec_reg_addr)
    );

    RXVDFF #(
        .width(32)
    ) exec_wr_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (alu_q),
        .q    (exec_reg_wr_data)
    );

    RXVDFF #(
        .width(commit_width)
    ) exec_complete_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_id),
        .q    (exec_complete_id)
    );

    RXVDFF exec_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_valid),
        .q    (exec_complete)
    );

    RXVDFF exec_reg_wr_en_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_valid & exec_have_writeback),
        .q    (exec_reg_wr_en)
    );

`ifdef FORMAL
    always_comb
        if (exec_alu_op == RXVTypes::ALU_SLT) assert ($signed(op1) < $signed(op2) == alu_q[0]);
    always_comb if (exec_alu_op == RXVTypes::ALU_SLTU) assert (op1 < op2 == alu_q[0]);
`endif

endmodule
