`default_nettype none

import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_uop;
import RXVCSR::RXVException;
import RXVTrace::trace_write_mem;

module RXVLSU #(
    parameter int commit_order = 3
) (
    input  logic                           clk,
    input  logic                           reset,
    input  logic                           icache_busy,
    output logic                           icache_invalidate,
    // From decode
    input  logic                           kill_valid,
    input  logic                           exec_valid,
    input  logic                           exec_have_writeback,
    input  phys_reg_tag                    exec_rd,
    input  logic        [commit_width-1:0] exec_id,
    input  logic        [            31:0] op1,
    input  logic        [            31:0] op2,
    input  logic        [            31:0] exec_immed,
    input  logic        [            31:2] exec_pc,
    input  logic        [            31:2] exec_next_pc,
    input  rxv_uop                         exec_uop,
    // Decode stall feedback, only set on cache-miss or uncached access where
    // it becomes a variable latency access
    output logic                           lsu_busy,
    // Result
    input  logic                           lsu_reg_busy,
    output phys_reg_tag                    lsu_reg_addr,
    output logic                           lsu_reg_wr_en,
    output logic        [            31:0] lsu_reg_wr_data,
    output logic                           lsu_complete,
    output logic        [commit_width-1:0] lsu_complete_id,
    // To data cache
    output logic        [            31:2] dcache_address,
    output logic                           dcache_valid,
    input  logic                           dcache_busy,
    input  logic        [            31:0] dcache_rdata,
    output logic                           dcache_wren,
    output logic        [             3:0] dcache_bytesel,
    output logic        [            31:0] dcache_wdata,
    output logic                           dcache_invalidate,
    output logic                           dcache_clean,
    // Exception handling
    output RXVException                    lsu_exception,
    output logic        [commit_width-1:0] lsu_except_id,
    output logic                           lsu_busy_kill,
    output logic                           lsu_resteer,
    output logic        [            31:2] lsu_resteer_tgt,
    output logic                           global_stall_start,
    output logic                           global_stall_end
);

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    typedef enum bit [1:0] {
        WIDTH_8  = 2'b00,
        WIDTH_16 = 2'b01,
        WIDTH_32 = 2'b11
    } lsu_width;

    typedef struct packed {
        phys_reg_tag rd;
        logic reg_wr_en;
        logic [commit_width-1:0] id;
        logic [3:0] read_mask;
        logic [1:0] addr_offset;
        lsu_width width;
        logic is_signed;
        logic valid;
    } lsu_op;

    // Stage 1:
    //   Generate address
    //   Rotate write data
    //   Issue to dcache
    // Stage 2:
    //   Present write data
    //   Busy: stall
    // Stage 3:
    //   Read result
    //   Rotate+mask read data
    //   Write to output register file port
    //   Stall on write port contention
    //     If this stalls then only because the access itself stalled in which
    //     case any newer load/store will have been killed.

    logic        [            31:0] address;
    logic        [            31:0] dcache_wdata_next;
    logic                           is_load;
    logic                           is_store;
    logic                           is_fencei;
    lsu_op                          op_stage1_next;
    lsu_op                          op_stage1;
    lsu_op                          op_stage2_next;
    lsu_op                          op_stage2;
    logic        [            31:0] lsu_reg_wr_data_next;
    phys_reg_tag                    lsu_reg_addr_next;
    logic                           lsu_reg_wr_en_next;
    logic                           lsu_complete_next;
    logic        [commit_width-1:0] lsu_complete_id_next;
    logic                           is_unaligned;
    lsu_width                       width;
    RXVException                    lsu_exception_next;
    logic                           lsu_busy_kill_next;
    logic                           lsu_busy_next;
    logic                           valid;
    logic                           lsu_resteer_next;
    logic        [            31:2] lsu_resteer_tgt_next;
    logic                           lsu_resteer_tgt_update;
    logic                           lsu_stall;
    logic                           fencei_pending;
    logic                           fencei_pending_next;
    logic                           dcache_clean_next;
    logic                           icache_invalidate_next;
    logic                           global_stall_start_next;
    logic                           global_stall_end_next;

    always_comb begin
        dcache_invalidate = 1'b0;
    end

    always_comb begin
        lsu_stall = dcache_busy | fencei_pending | dcache_clean | icache_invalidate;
    end

    always_comb begin
        global_stall_start_next = valid & is_fencei;
        global_stall_end_next   = fencei_pending & ~icache_busy & ~dcache_busy;
    end

    always_comb begin
        fencei_pending_next = fencei_pending;
        if (valid && is_fencei) fencei_pending_next = 1'b1;
        if (fencei_pending && !icache_busy && !dcache_busy) fencei_pending_next = 1'b0;
    end

    always_comb begin
        dcache_clean_next      = 1'b0;
        icache_invalidate_next = 1'b0;

        if (fencei_pending && !icache_busy && !dcache_busy) begin
            dcache_clean_next      = 1'b1;
            icache_invalidate_next = 1'b1;
        end
    end

    always_comb begin
        lsu_busy_kill_next = ((exec_valid & lsu_stall) | fencei_pending) & ~kill_valid;
        valid              = exec_valid & ~lsu_busy_kill_next;
    end

    always_comb begin
        lsu_busy_next = lsu_stall;
    end

    always_comb begin
        address        = op1 + exec_immed;
        dcache_address = address[31:2];

        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LBU, RXVTypes::UOP_SB: begin
                dcache_bytesel = 4'b1 << address[1:0];
                is_unaligned   = 1'b0;
            end
            RXVTypes::UOP_LH, RXVTypes::UOP_LHU, RXVTypes::UOP_SH: begin
                dcache_bytesel = 4'b11 << address[1] * 2;
                is_unaligned   = address[0];
            end
            default: begin
                dcache_bytesel = 4'b1111;
                is_unaligned   = |address[1:0];
            end
        endcase

        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LH, RXVTypes::UOP_LW, RXVTypes::UOP_LBU,
            RXVTypes::UOP_LHU: begin
                is_load   = 1'b1;
                is_store  = 1'b0;
                is_fencei = 1'b0;
            end
            RXVTypes::UOP_SB, RXVTypes::UOP_SH, RXVTypes::UOP_SW: begin
                is_store  = 1'b1;
                is_load   = 1'b0;
                is_fencei = 1'b0;
            end
            RXVTypes::UOP_FENCEI: begin
                is_fencei = 1'b1;
                is_load   = 1'b0;
                is_store  = 1'b0;
            end
            default: begin
                is_load   = 1'b0;
                is_store  = 1'b0;
                is_fencei = 1'b0;
            end
        endcase

        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LBU, RXVTypes::UOP_SB: width = WIDTH_8;
            RXVTypes::UOP_LH, RXVTypes::UOP_LHU, RXVTypes::UOP_SH: width = WIDTH_16;
            default: width = WIDTH_32;
        endcase

        op_stage1_next.rd          = exec_rd;
        op_stage1_next.reg_wr_en   = exec_have_writeback;
        op_stage1_next.id          = exec_id;
        op_stage1_next.read_mask   = dcache_bytesel;
        op_stage1_next.addr_offset = address[1:0];
        op_stage1_next.valid       = (((is_load | is_store) & ~is_unaligned) | is_fencei) & valid;
        op_stage1_next.width       = width;
        op_stage1_next.is_signed   = exec_uop == RXVTypes::UOP_LB || exec_uop == RXVTypes::UOP_LH;
    end

    always_comb begin
        op_stage2_next = op_stage1;
        if (lsu_stall) op_stage2_next = 'b0;
    end

    always_comb begin
        integer i;

        for (i = 0; i < 4; i = i + 1)
            lsu_reg_wr_data_next[8*i+:8] = dcache_rdata[8*i+:8] & {8{op_stage2.read_mask[i]}};
        lsu_reg_wr_data_next = lsu_reg_wr_data_next >> (5'(op_stage2.addr_offset) * 8);
        if (op_stage2.width == WIDTH_8 && op_stage2.is_signed)
            lsu_reg_wr_data_next = 32'($signed(lsu_reg_wr_data_next[7:0]));
        if (op_stage2.width == WIDTH_16 && op_stage2.is_signed)
            lsu_reg_wr_data_next = 32'($signed(lsu_reg_wr_data_next[15:0]));
        lsu_reg_addr_next    = op_stage2.rd;
        lsu_reg_wr_en_next   = op_stage2.valid & op_stage2.reg_wr_en;
        lsu_complete_next    = op_stage2.valid;
        lsu_complete_id_next = op_stage2.id;

        if (lsu_complete && lsu_reg_busy) begin
            lsu_reg_wr_data_next = lsu_reg_wr_data;
            lsu_reg_addr_next    = lsu_reg_addr;
            lsu_reg_wr_en_next   = lsu_reg_wr_en;
            lsu_complete_next    = lsu_complete;
            lsu_complete_id_next = lsu_complete_id;
        end
    end

    // If there is completion contention then we should have already killed
    // any newer uop
    RXVAssert #(
        .message("no LSU completion overflow")
    ) lsu_complete_overflow (
        .clk      (clk),
        .en       (lsu_complete && lsu_reg_busy),
        .condition(!op_stage2.valid)
    );

    always_comb begin
        lsu_exception_next.pc = exec_pc;
        lsu_exception_next.val = address;
        lsu_exception_next.cause = is_load ? RXVCSR::MCAUSE_LOAD_MISALIGN : RXVCSR::MCAUSE_STORE_MISALIGN;
        lsu_exception_next.valid = (is_load | is_store) & valid & is_unaligned;
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_SB: dcache_wdata_next = op2 << (address[1:0] * 8);
            RXVTypes::UOP_SH: dcache_wdata_next = op2 << (address[1] * 16);
            default: dcache_wdata_next = op2;
        endcase
    end

    always_comb begin
        dcache_wren = is_store;
    end

    always_comb begin
        dcache_valid = (is_load | is_store) & valid & ~is_unaligned;
    end

    always_comb begin
        lsu_resteer_next       = lsu_busy_kill_next | global_stall_end;
        lsu_resteer_tgt_next   = exec_valid && is_fencei ? exec_next_pc : exec_pc;
        lsu_resteer_tgt_update = exec_valid;
    end

`ifdef verilator
    always_ff @(posedge clk) begin
        int size;
        if (valid && !is_unaligned && is_store) begin
            case (exec_uop)
                RXVTypes::UOP_SB: size = 1;
                RXVTypes::UOP_SH: size = 2;
                RXVTypes::UOP_SW: size = 4;
                default: size = 4;
            endcase
            trace_write_mem(32'(exec_id), address, address, op2, size);
        end
    end
`endif

    RXVDFF #(
        .width(32)
    ) dcache_wdata_dff (
        .clk  (clk),
        .reset(reset),
        .en   (~lsu_stall),
        .d    (dcache_wdata_next),
        .q    (dcache_wdata)
    );

    RXVDFF #(
        .width($bits(lsu_op))
    ) lsu_op_stage1_dff (
        .clk  (clk),
        .reset(reset),
        .en   (~lsu_stall),
        .d    (op_stage1_next),
        .q    (op_stage1)
    );

    RXVDFF #(
        .width($bits(lsu_op))
    ) lsu_op_stage2_dff (
        .clk  (clk),
        .reset(reset),
        .en   (~lsu_reg_busy),
        .d    (op_stage2_next),
        .q    (op_stage2)
    );

    RXVDFF #(
        .width(32)
    ) lsu_reg_wr_data_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_reg_wr_data_next),
        .q    (lsu_reg_wr_data)
    );

    RXVDFF #(
        .width($bits(phys_reg_tag))
    ) lsu_reg_addr_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_reg_addr_next),
        .q    (lsu_reg_addr)
    );

    RXVDFF #(
        .width(commit_width)
    ) lsu_complete_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_complete_id_next),
        .q    (lsu_complete_id)
    );

    RXVDFF lsu_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_complete_next),
        .q    (lsu_complete)
    );

    RXVDFF lsu_reg_wr_en_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_reg_wr_en_next),
        .q    (lsu_reg_wr_en)
    );

    RXVDFF lsu_busy_kill_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_busy_kill_next),
        .q    (lsu_busy_kill)
    );

    RXVDFF lsu_busy_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_busy_next),
        .q    (lsu_busy)
    );

    RXVDFF #(
        .width($bits(RXVCSR::RXVException))
    ) lsu_exception_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_exception_next),
        .q    (lsu_exception)
    );

    RXVDFF #(
        .width($bits(lsu_except_id))
    ) lsu_except_id_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (exec_id),
        .q    (lsu_except_id)
    );

    RXVDFF lsu_resteer_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (lsu_resteer_next),
        .q    (lsu_resteer)
    );

    RXVDFF #(
        .width(30)
    ) lsu_resteer_tgt_dff (
        .clk  (clk),
        .reset(reset),
        .en   (lsu_resteer_tgt_update),
        .d    (lsu_resteer_tgt_next),
        .q    (lsu_resteer_tgt)
    );

    RXVDFF fencei_pending_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fencei_pending_next),
        .q    (fencei_pending)
    );

    RXVDFF dcache_clean_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dcache_clean_next),
        .q    (dcache_clean)
    );

    RXVDFF icache_invalidate_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (icache_invalidate_next),
        .q    (icache_invalidate)
    );

    RXVDFF global_stall_start_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (global_stall_start_next),
        .q    (global_stall_start)
    );

    RXVDFF global_stall_end_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (global_stall_end_next),
        .q    (global_stall_end)
    );

endmodule
