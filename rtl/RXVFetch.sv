module RXVFetch(
    input logic clk,
    input logic reset,
    output logic [31:0] i_addr,
    input logic [31:0] i_data,
    output logic [31:0] instruction,
`ifdef RXV_RVFI
    output logic fd_intr,
`endif
    output logic [31:0] fd_pc,
    output logic fd_valid,
    input logic wf_finish_flush,
    input logic w_exception,
    input logic df_flush,
    input logic f_write_pc,
    input logic [31:0] f_write_pc_val,
    input logic w_take_interrupt,
    input logic d_load_delay
);

reg [31:0] reset_vector = 32'b0;
// verilator lint_off BLKANDNBLK
reg [31:0] pc;
// verilator lint_on BLKANDNBLK
reg delay_slot;
reg flushing_pipeline;

wire insert_nop         = flushing_pipeline | delay_slot;
wire f_flush_pipeline   = df_flush & fd_valid & ~w_exception;
wire stall              = d_load_delay || f_flush_pipeline || (flushing_pipeline && !wf_finish_flush);
wire [31:0] next_pc     = f_write_pc ? f_write_pc_val :
                          stall ? pc :
                          pc + 32'd4;

assign i_addr           = next_pc;
assign instruction = insert_nop || 1'b0 ? 32'h00000013 : i_data;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        flushing_pipeline <= 1'b0;
        delay_slot <= 1'b0;
        fd_pc <= reset_vector;
        fd_valid <= 1'b0;
`ifdef RXV_RVFI
        fd_intr <= 1'b0;
`endif
    end else begin
        if (wf_finish_flush)
            flushing_pipeline <= 1'b0;
        if (f_flush_pipeline)
            flushing_pipeline <= 1'b1;

        delay_slot <= d_load_delay && !w_exception;
        fd_pc <= next_pc;
        fd_valid <= !stall || f_write_pc;
`ifdef RXV_RVFI
        fd_intr <= w_take_interrupt;
`endif
    end
end

always_ff @(posedge clk or posedge reset)
    if (reset)
        pc <= reset_vector - 32'd4;
    else begin
        pc <= next_pc;
    end

endmodule