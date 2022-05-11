`default_nettype none

import RXVTypes::phys_reg_tag;
import RXVTypes::rxv_uop;
import RXVTypes::commit_width;
import RXVCSR::RXVException;
import RXVTrace::trace_write_mem;
import RXVTrace::trace_read_mem;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;

module RXVLSU #(
    parameter line_size_bytes = 16
) (
    input  logic                            clk,
    input  logic                            reset,
    input  logic                            icache_busy,
    output logic                            icache_invalidate,
    // From decode
    input  logic                            kill_valid,
    input  logic                            exec_valid,
    input  logic                            exec_have_writeback,
    input  phys_reg_tag                     exec_rd,
    input  logic         [commit_width-1:0] exec_id,
    input  logic         [            31:0] op1,
    input  logic         [            31:0] op2,
    input  logic         [            31:0] exec_immed,
    input  logic         [            31:2] exec_pc,
    input  logic         [            31:2] exec_next_pc,
    input  rxv_uop                          exec_uop,
    // Decode stall feedback, only set on cache-miss or uncached access where
    // it becomes a variable latency access
    output logic                            lsu_busy,
    // Result
    input  logic                            lsu_reg_busy,
    output phys_reg_tag                     lsu_reg_addr,
    output logic                            lsu_reg_wr_en,
    output logic         [            31:0] lsu_reg_wr_data,
    output logic                            lsu_complete,
    output logic         [commit_width-1:0] lsu_complete_id,
    // To data cache
    output logic         [            31:2] dcache_address,
    output logic                            dcache_valid,
    input  logic                            dcache_busy,
    input  logic         [            31:0] dcache_rdata,
    output logic                            dcache_wren,
    output logic         [             3:0] dcache_bytesel,
    output logic         [            31:0] dcache_wdata,
    output logic                            dcache_invalidate,
    output logic                            dcache_clean,
    output logic         [            31:2] dcache_phys,
    output logic                            dcache_phys_valid,
    input  logic                            dcache_device_memory,
    // From TLB
    // verilator lint_off UNUSED
    input  translation_t                    lsu_translation,
    // verilator lint_on UNUSED
    input  logic                            lsu_tlb_busy,
    output tlb_inv_op                       lsu_tlb_inv_op,
    output logic         [   asid_bits-1:0] lsu_tlb_inv_asid,
    output logic         [           31:12] lsu_tlb_inv_addr,
    // Exception handling
    output RXVException                     lsu_exception,
    output logic         [commit_width-1:0] lsu_except_id,
    output logic                            lsu_busy_kill,
    output logic                            lsu_resteer,
    output logic         [            31:2] lsu_resteer_tgt,
    output logic                            global_stall_start,
    output logic                            global_stall_end
);

    localparam offset_bits = $clog2(line_size_bytes / 4);
    localparam reservation_bits = 30 - offset_bits;

    always_comb begin
        unique case ({
            valid, exec_uop
        })
            {1'b1, RXVTypes::UOP_SFENCE_VMA_ALL} : lsu_tlb_inv_op = RXVMMU::TLB_INV_ALL;
            {1'b1, RXVTypes::UOP_SFENCE_VMA_ASID} : lsu_tlb_inv_op = RXVMMU::TLB_INV_ASID_ONLY;
            {1'b1, RXVTypes::UOP_SFENCE_VMA_ADDR} : lsu_tlb_inv_op = RXVMMU::TLB_INV_ADDR_ONLY;
            {1'b1, RXVTypes::UOP_SFENCE_VMA_ASID_ADDR} : lsu_tlb_inv_op = RXVMMU::TLB_INV_ASID_ADDR;
            default: lsu_tlb_inv_op = RXVMMU::TLB_INV_NONE;
        endcase
        lsu_tlb_inv_addr = op2[31:12];
        lsu_tlb_inv_asid = op1[asid_bits-1:0];
    end

    // verilator lint_off UNUSED
    function [reservation_bits-1:0] get_reservation_addr;
        input [31:2] address_in;
        get_reservation_addr = address_in[2+offset_bits+:reservation_bits];
    endfunction
    // verilator lint_on UNUSED

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
        logic is_sc;
        logic is_store;
        logic is_amo;
        logic reservation_held;
        logic [31:0] address;
`ifdef RXV_TRACE
        logic [31:0] store_data;
        logic [31:12] phys;
`endif
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

    logic        [                31:0] address;
    logic        [                31:0] dcache_wdata_next;
    logic                               is_load;
    logic                               is_invalid_amo;
    logic                               is_store;
    logic                               is_fencei;
    logic                               is_sfence_vma;
    logic        [                 3:0] next_read_mask;
    lsu_op                              op_stage1_next;
    lsu_op                              op_stage1;
    lsu_op                              op_stage2_next;
    // verilator lint_off UNUSED
    lsu_op                              op_stage2;
    // verilator lint_on UNUSED
    logic        [                31:0] lsu_reg_wr_data_next;
    phys_reg_tag                        lsu_reg_addr_next;
    logic                               lsu_reg_wr_en_next;
    logic                               lsu_complete_next;
    logic                               lsu_complete_reg;
    logic        [    commit_width-1:0] lsu_complete_id_next;
    logic                               is_unaligned;
    lsu_width                           width;
    RXVException                        lsu_exception_next;
    logic        [    commit_width-1:0] lsu_except_id_next;
    logic                               lsu_busy_kill_next;
    logic                               lsu_busy_next;
    logic                               valid;
    logic                               lsu_resteer_next;
    logic        [                31:2] lsu_resteer_tgt_next;
    logic                               lsu_resteer_tgt_update;
    logic                               lsu_stall;
    logic                               fencei_pending;
    logic                               fencei_pending_next;
    logic                               dcache_clean_next;
    logic                               icache_invalidate_next;
    logic                               global_stall_start_next;
    logic                               global_stall_end_next;
    logic                               fencei_active;
    logic                               fencei_active_next;
    logic        [reservation_bits-1:0] reservation_address;
    logic        [reservation_bits-1:0] reservation_address_next;
    logic                               reservation_held;
    logic                               reservation_held_next;
    logic                               reservation_matches;

    always_comb begin
        dcache_invalidate = 1'b0;
    end

    always_comb begin
        lsu_complete = lsu_reg_busy && lsu_reg_wr_en ? 1'b0 : lsu_complete_reg;
    end

    always_comb begin
        lsu_stall = dcache_busy | lsu_tlb_busy | fencei_pending | dcache_clean | icache_invalidate;
    end

    always_comb begin
        fencei_active_next = fencei_active;
        if (fencei_pending && !fencei_pending_next) fencei_active_next = 1'b1;
        if (fencei_active && !icache_busy && !dcache_busy && !dcache_clean && !icache_invalidate)
            fencei_active_next = 1'b0;
    end

    always_comb begin
        global_stall_start_next = valid & is_fencei;
        global_stall_end_next   = fencei_active & ~fencei_active_next;
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
        valid              = exec_valid & ~lsu_busy_kill_next & ~kill_valid & ~is_invalid_amo;
    end

    always_comb begin
        lsu_busy_next = lsu_stall;
    end

    always_comb begin
        address        = op1 + exec_immed;
        dcache_address = address[31:2];
    end

    always_comb begin
        reservation_held_next    = reservation_held;
        reservation_address_next = reservation_address;

        if (valid && exec_uop == RXVTypes::UOP_SC) reservation_held_next = 1'b0;
        if (valid && get_reservation_addr(address[31:2]) != reservation_address)
            reservation_held_next = 1'b0;

        if (valid && exec_uop == RXVTypes::UOP_LR) begin
            reservation_held_next    = ~dcache_device_memory;
            reservation_address_next = get_reservation_addr(address[31:2]);
        end

        reservation_matches = reservation_held &&
            get_reservation_addr(address[31:2]) == reservation_address;
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LBU: next_read_mask = 4'b1 << address[1:0];
            RXVTypes::UOP_LH, RXVTypes::UOP_LHU: next_read_mask = 4'b11 << address[1] * 2;
            default: next_read_mask = 4'b1111;
        endcase
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LBU, RXVTypes::UOP_SB: is_unaligned = 1'b0;
            RXVTypes::UOP_LH, RXVTypes::UOP_LHU, RXVTypes::UOP_SH: is_unaligned = address[0];
            default: is_unaligned = |address[1:0];
        endcase

        unique case (op_stage1.width)
            WIDTH_8:  dcache_bytesel = 4'b1 << op_stage1.addr_offset;
            WIDTH_16: dcache_bytesel = 4'b11 << op_stage1.addr_offset[1] * 2;
            default:  dcache_bytesel = 4'b1111;
        endcase


        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LH, RXVTypes::UOP_LW, RXVTypes::UOP_LW_ATOMIC,
            RXVTypes::UOP_LBU, RXVTypes::UOP_LHU, RXVTypes::UOP_LR: begin
                is_load       = 1'b1;
                is_store      = 1'b0;
                is_fencei     = 1'b0;
                is_sfence_vma = 1'b0;
            end
            RXVTypes::UOP_SB, RXVTypes::UOP_SH, RXVTypes::UOP_SW, RXVTypes::UOP_SC: begin
                is_store      = 1'b1;
                is_load       = 1'b0;
                is_fencei     = 1'b0;
                is_sfence_vma = 1'b0;
            end
            RXVTypes::UOP_FENCEI: begin
                is_fencei     = 1'b1;
                is_load       = 1'b0;
                is_store      = 1'b0;
                is_sfence_vma = 1'b0;
            end
            RXVTypes::UOP_SFENCE_VMA_ALL, RXVTypes::UOP_SFENCE_VMA_ASID,
            RXVTypes::UOP_SFENCE_VMA_ADDR, RXVTypes::UOP_SFENCE_VMA_ASID_ADDR: begin
                is_fencei     = 1'b0;
                is_load       = 1'b0;
                is_store      = 1'b0;
                is_sfence_vma = 1'b1;
            end
            default: begin
                is_load       = 1'b0;
                is_store      = 1'b0;
                is_fencei     = 1'b0;
                is_sfence_vma = 1'b0;
            end
        endcase

        is_invalid_amo = op_stage1.valid && op_stage1.is_amo && dcache_device_memory;

        unique case (exec_uop)
            RXVTypes::UOP_LB, RXVTypes::UOP_LBU, RXVTypes::UOP_SB: width = WIDTH_8;
            RXVTypes::UOP_LH, RXVTypes::UOP_LHU, RXVTypes::UOP_SH: width = WIDTH_16;
            default: width = WIDTH_32;
        endcase

        op_stage1_next.rd = exec_rd;
        op_stage1_next.reg_wr_en = exec_have_writeback;
        op_stage1_next.id = exec_id;
        op_stage1_next.read_mask = next_read_mask;
        op_stage1_next.addr_offset = address[1:0];
        op_stage1_next.valid = (((is_load | is_store) & ~is_unaligned) | is_fencei | is_sfence_vma) & valid;
        op_stage1_next.width = width;
        op_stage1_next.is_signed = exec_uop == RXVTypes::UOP_LB || exec_uop == RXVTypes::UOP_LH;
        op_stage1_next.is_sc = exec_uop == RXVTypes::UOP_SC;
        op_stage1_next.is_store = is_store;
        op_stage1_next.reservation_held = reservation_matches;
        op_stage1_next.address = address;
        op_stage1_next.is_amo = (exec_uop == RXVTypes::UOP_LW_ATOMIC || exec_uop == RXVTypes::UOP_LR || exec_uop == RXVTypes::UOP_SC);
`ifdef RXV_TRACE
        op_stage1_next.store_data = op2;
        op_stage1_next.phys       = 20'b0;
`endif  // RXV_TRACE
    end

    always_comb begin
        op_stage2_next = op_stage1;
`ifdef RXV_TRACE
        op_stage2_next.phys = lsu_translation.pa[31:12];
`endif  // RXV_TRACE
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
        if (op_stage2.is_sc) lsu_reg_wr_data_next = {31'b0, ~op_stage2.reservation_held};
        lsu_reg_addr_next    = op_stage2.rd;
        lsu_reg_wr_en_next   = op_stage2.valid & op_stage2.reg_wr_en;
        lsu_complete_next    = op_stage2.valid;
        lsu_complete_id_next = op_stage2.id;

        if (lsu_complete_reg && lsu_reg_busy && lsu_reg_wr_en) begin
            lsu_reg_wr_data_next = lsu_reg_wr_data;
            lsu_reg_addr_next    = lsu_reg_addr;
            lsu_reg_wr_en_next   = lsu_reg_wr_en;
            lsu_complete_next    = lsu_complete_reg;
            lsu_complete_id_next = lsu_complete_id;
        end
    end

    // If there is completion contention then we should have already killed
    // any newer uop
    RXVAssert #(
        .message("no LSU completion overflow")
    ) lsu_complete_overflow (
        .clk      (clk),
        .en       (lsu_complete && lsu_reg_busy && lsu_reg_wr_en),
        .condition(!(op_stage2.valid && op_stage2.reg_wr_en))
    );

    always_comb begin
        lsu_exception_next.pc = exec_pc;
        lsu_exception_next.val = is_invalid_amo ? op_stage1.address : address;
        lsu_exception_next.cause = is_invalid_amo ? RXVCSR::CAUSE_LOAD_ACCESS_FAULT :
        is_load ? RXVCSR::CAUSE_LOAD_MISALIGN : RXVCSR::CAUSE_STORE_MISALIGN;
        lsu_exception_next.valid = ((is_load | is_store) & valid & is_unaligned) | is_invalid_amo;
        lsu_exception_next.irq = 1'b0;

        lsu_except_id_next = is_invalid_amo ? op_stage1.id : exec_id;
    end

    always_comb begin
        unique case (exec_uop)
            RXVTypes::UOP_SB: dcache_wdata_next = op2 << (address[1:0] * 8);
            RXVTypes::UOP_SH: dcache_wdata_next = op2 << (address[1] * 16);
            default: dcache_wdata_next = op2;
        endcase
    end

    always_comb begin
        dcache_wren = op_stage1.valid & op_stage1.is_store;
        dcache_phys = {lsu_translation.pa, op_stage1.address[11:2]};
        dcache_phys_valid = op_stage1.valid & ~lsu_tlb_busy & lsu_translation.valid & ~is_invalid_amo;
    end

    always_comb begin
        dcache_valid = (is_load | is_store) & valid & ~is_unaligned;
        if (exec_uop == RXVTypes::UOP_SC && !reservation_matches) dcache_valid = 1'b0;
    end

    always_comb begin
        lsu_resteer_next = lsu_busy_kill_next | global_stall_end | (is_sfence_vma & valid);
        lsu_resteer_tgt_next = exec_valid && (is_fencei || is_sfence_vma) ? exec_next_pc : exec_pc;
        lsu_resteer_tgt_update = exec_valid && !kill_valid;
    end

`ifdef RXV_TRACE
    always_ff @(posedge clk) begin
        int size;

        if (lsu_complete_next && op_stage2.is_store) begin
            unique case (op_stage2.width)
                WIDTH_8:  size = 1;
                WIDTH_16: size = 2;
                WIDTH_32: size = 4;
                default:  size = 4;
            endcase
            trace_write_mem(32'(op_stage2.id), op_stage2.address, {
                            op_stage2.phys, op_stage2.address[11:0]}, op_stage2.store_data, size);
        end

        if (lsu_complete_next && lsu_reg_wr_en_next && !op_stage2.is_sc) begin
            unique case (op_stage2.width)
                WIDTH_8:  size = 1;
                WIDTH_16: size = 2;
                WIDTH_32: size = 4;
                default:  size = 4;
            endcase
            trace_read_mem(32'(op_stage2.id), op_stage2.address, {
                           op_stage2.phys, op_stage2.address[11:0]
                           },
                           lsu_reg_wr_data_next, size);
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
        .en   (1'b1),
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
        .q    (lsu_complete_reg)
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
        .d    (lsu_except_id_next),
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

    RXVDFF fencei_active_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fencei_active_next),
        .q    (fencei_active)
    );

    RXVDFF #(
        .width(reservation_bits)
    ) reservation_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (reservation_address_next),
        .q    (reservation_address)
    );

    RXVDFF reservation_held_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (reservation_held_next),
        .q    (reservation_held)
    );

endmodule
