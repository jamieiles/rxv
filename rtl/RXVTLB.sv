`include "RXV.svh"

import RXVMMU::sv32_pte_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;
import RXVMMU::pmp_perms;

module RXVTLB #(
    parameter int num_entries = 8
) (
    input  logic                         clk,
    input  logic                         reset,
    // To/from fetch/LSU
    input  logic         [        31:12] va,
    input  logic         [asid_bits-1:0] active_asid,
    input  logic                         valid,
    input  logic                         grant,
    output translation_t                 translation,
    output logic                         access_fault,
    output logic                         busy,
    input  tlb_inv_op                    tlb_op,
    input  logic         [asid_bits-1:0] inv_asid,
    input  logic         [        31:12] inv_addr,
    // To/from walker
    output logic         [        31:12] walk_va,
    output logic                         walk_valid,
    input  logic                         walk_busy,
    // verilator lint_off UNUSED
    input  sv32_pte_t                    walk_pte,
    // verilator lint_on UNUSED
    input  logic                         walk_is_megapage,
    input  logic                         walk_translation_error,
    input  logic                         walk_pmp_violation,
    output logic         [         31:2] phys_addr,
    //verilator lint_off UNUSED
    input  pmp_perms                     phys_perms,
    //verilator lint_on UNUSED
    // Global control
    input  logic                         enabled
);

    localparam way_bits = $clog2(num_entries);

    typedef struct packed {
        translation_t translation;
        logic [31:12] va;
        logic is_megapage;
    } tlb_entry_t;

    typedef enum bit [1:0] {
        STATE_READY = 2'b00,
        STATE_WALK = 2'b01,
        STATE_FILL = 2'b10,
        STATE_RESTART = 2'b11
    } state_t;

    logic         [      way_bits-1:0] hit_index;
    logic                              hit;
    logic         [      way_bits-1:0] lru_out;
    tlb_entry_t                        all_entries        [num_entries];
    logic         [   num_entries-1:0] hits;
    logic                              walk_va_update;
    logic                              lru_update;
    logic                              walk_valid_next;
    logic                              access_fault_next;
    translation_t                      translation_next;
    translation_t                      bypass_translation;
    state_t                            state;
    state_t                            next_state;
    logic                              translation_update;
    logic         [$bits(state_t)-1:0] state_q;
    logic                              multihit;

    TLBPLRU #(
        .width(num_entries)
    ) TLBPLRU (
        .clk       (clk),
        .reset     (reset),
        .access_way(hit_index),
        .valid     (lru_update),
        .lru_out   (lru_out)
    );

    function logic entry_va_matches;
        input tlb_entry_t entry;
        input logic [31:12] address;

        begin
            entry_va_matches = 1'b0;
            entry_va_matches |= (entry.translation.valid && !entry.is_megapage && entry.va == address);
            entry_va_matches |= (entry.translation.valid && entry.is_megapage && entry.va[31:22] == address[31:22]);
        end
    endfunction

    function translation_t add_offset;
        // verilator lint_off UNUSED
        input tlb_entry_t entry;
        // verilator lint_on UNUSED

        begin
            translation_t r;

            r = entry.translation;
            if (entry.is_megapage) r.pa = {r.pa[31:22], va[21:12]};
            add_offset = r;
        end
    endfunction

    genvar way;
    generate
        for (way = 0; way < num_entries; ++way) begin : entries
            tlb_entry_t entry;
            tlb_entry_t entry_next;
            logic       entry_hit;

            assign all_entries[way] = entry;
            assign hits[way]        = entry_hit;

            always_comb begin
                entry_next = entry;

                unique case (tlb_op)
                    // verilog_format: off
                    RXVMMU::TLB_INV_ALL: entry_next = tlb_entry_t'(1'b0);
                    RXVMMU::TLB_INV_ASID_ONLY:
                        entry_next = entry.translation.asid == inv_asid &&
                            !entry.translation.page_global ? tlb_entry_t'(1'b0) :
                            entry;
                    RXVMMU::TLB_INV_ADDR_ONLY:
                        entry_next = entry_va_matches(entry, inv_addr) ?
                            tlb_entry_t'(1'b0) : entry;
                    RXVMMU::TLB_INV_ASID_ADDR:
                        entry_next = entry.translation.asid == inv_asid &&
                            entry_va_matches(entry, inv_addr) && !entry.translation.page_global ?
                            tlb_entry_t'(1'b0) : entry;
                    default: entry_next = entry;
                    // verilog_format: on
                endcase

                if (state == STATE_FILL && way == lru_out && !walk_translation_error &&
                    !walk_pmp_violation && walk_pte.valid) begin
                    // FIXME: handle 34-bit PA
                    entry_next.translation.pa          = 20'({walk_pte.ppn1, walk_pte.ppn0});
                    entry_next.translation.dirty       = walk_pte.dirty;
                    entry_next.translation.accessed    = walk_pte.accessed;
                    entry_next.translation.page_global = walk_pte.page_global;
                    entry_next.translation.user        = walk_pte.user;
                    entry_next.translation.exec        = walk_pte.exec;
                    entry_next.translation.write       = walk_pte.write;
                    entry_next.translation.read        = walk_pte.read;
                    entry_next.translation.valid       = walk_pte.valid;
                    entry_next.translation.asid        = active_asid;
                    entry_next.translation.pmp         = phys_perms;
                    entry_next.va                      = walk_va;
                    entry_next.is_megapage             = walk_is_megapage;
                end
            end

            always_comb begin
                entry_hit = entry_va_matches(entry, va) &&
                    (entry.translation.asid == active_asid || entry.translation.page_global);
            end

            RXVDFF #(
                .width($bits(entry))
            ) entry_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (entry_next),
                .q    (entry)
            );
        end
    endgenerate

`ifdef verilator
    RXVAssert no_inval_during_fill (
        .clk      (clk),
        .en       (state != STATE_READY),
        .condition(tlb_op == RXVMMU::TLB_INV_NONE)
    );
`endif  // verilator

    always_comb begin
        phys_addr = enabled ? 30'({walk_pte.ppn1, walk_pte.ppn0, 10'b0}) : {va, 10'b0};
    end

    always_comb begin
        bypass_translation.pa          = va;
        bypass_translation.dirty       = 1'b1;
        bypass_translation.accessed    = 1'b1;
        bypass_translation.page_global = 1'b1;
        bypass_translation.user        = 1'b1;
        bypass_translation.exec        = 1'b1;
        bypass_translation.write       = 1'b1;
        bypass_translation.read        = 1'b1;
        bypass_translation.valid       = 1'b1;
        bypass_translation.asid        = 'b0;
        bypass_translation.pmp         = access_fault ? pmp_perms'('b0) : phys_perms;
    end

    always_comb begin
        access_fault_next = grant && !enabled && walk_pmp_violation;
    end

    always_comb begin
        integer i;
        logic   hit_processed;

        multihit = 1'b0;
        hit_processed = 1'b0;
        hit = ((state == STATE_RESTART || (state == STATE_READY && valid)) && |hits) || (!enabled && valid);
        hit_index = 'b0;
        translation_next = valid ? 'b0 : translation;
        for (i = 0; i < num_entries; ++i) begin
            if (hit_processed && hits[i]) multihit = 1'b1;
            if (hits[i]) hit_processed = 1'b1;
            hit_index |= {way_bits{hits[i]}} & way_bits'(i);
            translation_next |= {$bits(translation_next) {hits[i]}} & add_offset(all_entries[i]);
        end

        translation_next |= {$bits(translation_next) {~enabled & valid}} & bypass_translation;

        translation_update = hit | valid;
    end

    RXVAssert no_multihit (
        .clk      (clk),
        .en       (1'b1),
        .condition(!multihit)
    );

    always_comb begin
        lru_update = hit && (state == STATE_READY || state == STATE_RESTART);
    end

    always_comb begin
        next_state = state;

        case (state)
            STATE_READY: next_state = (valid && !hit) ? STATE_WALK : STATE_READY;
            STATE_WALK: next_state = !walk_busy && !walk_valid ? STATE_FILL : STATE_WALK;
            STATE_FILL: next_state = STATE_RESTART;
            STATE_RESTART: next_state = STATE_READY;
            default: next_state = STATE_READY;
        endcase
    end

    always_comb begin
        busy = state != STATE_READY;
    end

    always_comb begin
        walk_va_update  = state == STATE_READY && next_state == STATE_WALK;
        walk_valid_next = next_state == STATE_WALK && (state != STATE_WALK || !grant);
    end

    always_comb begin
        state = state_t'(state_q);
    end

    RXVDFF #(
        .width($bits(state))
    ) state_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_state),
        .q    (state_q)
    );

    RXVDFF #(
        .width($bits(va))
    ) walk_va_dff (
        .clk  (clk),
        .reset(reset),
        .en   (walk_va_update),
        .d    (va),
        .q    (walk_va)
    );

    RXVDFF walk_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (walk_valid_next),
        .q    (walk_valid)
    );

    RXVDFF #(
        .width($bits(translation))
    ) translation_dff (
        .clk  (clk),
        .reset(reset),
        .en   (translation_update),
        .d    (translation_next),
        .q    (translation)
    );

    RXVDFF access_fault_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (access_fault_next),
        .q    (access_fault)
    );

endmodule
