`include "RXV.svh"
import RXVTypes::rxv_prediction;
import RXVMMU::translation_t;
import RXVMMU::asid_bits;
import RXVCSR::privilege_t;
import RXVCSR::mstatus_t;

module RXVFetchWrapper #(
    parameter logic [31:0] reset_address = 32'h80000000
) (
    input  logic                       clk,
    input  logic                       reset,
    input  privilege_t                 current_privilege,
    // verilator lint_off UNUSED
    input  mstatus_t                   mstatus,
    input  logic                       except_valid,
    input  logic                       exception_pending,
    input  logic                       global_stall_active,
    input  logic                       irq_pending,
    output logic                       fetch_idle,
    output logic       [         31:2] irq_epc,
    // To instruction cache
    output logic       [         31:2] icache_address,
    output logic                       icache_valid,
    input  logic                       icache_busy,
    input  logic       [         31:0] icache_instr,
    output logic       [         31:2] icache_phys,
    output logic                       icache_phys_valid,
    // TLB
    output logic                       fetch_tlb_valid,
    input  logic       [        31:12] tlb_pa,
    input  logic                       tlb_dirty,
    input  logic                       tlb_accessed,
    input  logic                       tlb_page_global,
    input  logic                       tlb_user,
    input  logic                       tlb_exec,
    input  logic                       tlb_write,
    input  logic                       tlb_read,
    input  logic                       tlb_valid,
    input  logic       [asid_bits-1:0] tlb_asid,
    input  logic                       tlb_busy,
    // To branch predictor
    output logic       [         31:2] branch_predict_address,
    input  logic                       branch_predict_valid,
    input  logic       [         31:2] branch_prediction,
    input  logic                       branch_predict_taken,
    input  logic       [          1:0] branch_predict_strength,
    // Decode resteer
    input  logic                       decode_resteer,
    input  logic       [         31:2] decode_resteer_tgt,
    // Decode stall
    input  logic                       decode_fe_stall,
    // To decode
    output logic                       decode_valid,
    output logic                       decode_page_fault,
    output logic                       decode_pmp_fault,
    output logic       [         31:2] decode_pc,
`ifdef RXV_TRACE
    output logic       [         31:2] decode_phys,
`endif  // RXV_TRACE
    output logic       [         31:2] decode_next_pc,
    output logic       [         31:0] decode_instr,
    output logic                       decode_predicted,
    output logic                       decode_predict_taken,
    output logic       [          1:0] decode_predict_strength,
    output logic       [         31:2] decode_prediction,
    // Exec branch resolution
    input  logic                       exec_resteer,
    input  logic       [         31:2] exec_resteer_tgt,
    // Exception handling
    input  logic                       exception_resteer,
    input  logic       [         31:2] exception_resteer_tgt
);

    rxv_prediction predict_in;
    rxv_prediction predict_out;
    translation_t  fetch_translation;
    logic          fetch_access_fault;

    assign predict_in.predicted        = branch_predict_valid;
    assign predict_in.prediction       = branch_prediction;
    assign predict_in.predict_taken    = branch_predict_taken;
    assign predict_in.predict_strength = branch_predict_strength;

    assign decode_predicted            = predict_out.predicted;
    assign decode_predict_taken        = predict_out.predict_taken;
    assign decode_predict_strength     = predict_out.predict_strength;
    assign decode_prediction           = predict_out.prediction;

    RXVFetch #(
        .reset_address(reset_address)
    ) RXVFetch (
        .prediction       (predict_in),
        .decode_prediction(predict_out),
        .fetch_tlb_busy   (tlb_busy),
        .*
    );

    always_comb begin
        fetch_translation.pa          = tlb_pa;
        fetch_translation.dirty       = tlb_dirty;
        fetch_translation.accessed    = tlb_accessed;
        fetch_translation.page_global = tlb_page_global;
        fetch_translation.user        = tlb_user;
        fetch_translation.exec        = tlb_exec;
        fetch_translation.write       = tlb_write;
        fetch_translation.read        = tlb_read;
        fetch_translation.valid       = tlb_valid;
        fetch_translation.asid        = tlb_asid;
        fetch_translation.pmp         = 3'b111;
        fetch_access_fault            = 1'b0;
    end

endmodule
