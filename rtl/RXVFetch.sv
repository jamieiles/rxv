`include "RXV.svh"
import RXVTypes::rxv_prediction;
import RXVMMU::translation_t;
import RXVCSR::privilege_t;
import RXVCSR::mstatus_t;
import RXVCSR::effective_privilege;

module RXVFetch #(
    parameter logic [31:0] reset_address = 32'h80000000
) (
    input  logic                  clk,
    input  logic                  reset,
    input  privilege_t            current_privilege,
    // verilator lint_off UNUSED
    input  mstatus_t              mstatus,
    // verilator lint_on UNUSED
    input  logic                  except_valid,
    input  logic                  exception_pending,
    input  logic                  global_stall_active,
    input  logic                  irq_pending,
    output logic                  fetch_idle,
    output logic          [ 31:2] irq_epc,
    // To instruction cache
    output logic          [ 31:2] icache_address,
    output logic                  icache_valid,
    input  logic                  icache_busy,
    input  logic          [ 31:0] icache_instr,
    // From instruction TLB
    output logic                  fetch_tlb_valid,
    output logic          [ 31:2] icache_phys,
    output logic                  icache_phys_valid,
    // verilator lint_off UNUSED
    input  translation_t          fetch_translation,
    // verilator lint_on UNUSED
    input  logic                  fetch_tlb_busy,
    // To branch predictor
    output logic          [ 31:2] branch_predict_address,
    input  rxv_prediction         prediction,
    // Decode resteer
    input  logic                  decode_resteer,
    input  logic          [ 31:2] decode_resteer_tgt,
    // Decode front-end stall
    input  logic                  decode_fe_stall,
    // To decode
    output logic                  decode_valid,
    output logic                  decode_page_fault,
    output logic          [ 31:2] decode_pc,
`ifdef RXV_TRACE
    output logic          [31:12] decode_phys,
`endif  // RXV_TRACE
    output logic          [ 31:2] decode_next_pc,
    output logic          [ 31:0] decode_instr,
    output rxv_prediction         decode_prediction,
    // Exec branch resolution
    input  logic                  exec_resteer,
    input  logic          [ 31:2] exec_resteer_tgt,
    // Exception
    input  logic                  exception_resteer,
    input  logic          [ 31:2] exception_resteer_tgt
);

    typedef struct packed {
        logic [31:2] pc;
        logic [31:2] next_pc;
        logic [31:0] instr;
        logic page_fault;
        rxv_prediction prediction;
`ifdef RXV_TRACE
        logic [31:12] phys;
`endif  // RXV_TRACE
    } fetch_packet;

    /*
     * icache_address is a registered output from a variety of sources,
     * when not stalling icache_valid is high, the fetched address is passed to
     * the next stage and the PC updated.
     *
     * On the next cycle we get an instruction back if !icache_busy, otherwise
     * we need to resteer the fetch address to retry the fetch until !busy.
     * Once !busy we can take pc+4 and the fetched address and write them to the
     * decode stage along with valid+instruction data and prediction state.
     *
     * Splitting the PC generation and cache lookup into separate stages adds
     * an additional cycle on branch mispredict but increases Fmax by ~40%.
     */

    logic          [31:2] pc;
    logic          [31:2] next_pc;
    logic          [31:2] fetched_pc;
    logic          [31:2] fetched_pc_next;
    logic          [31:2] next_seq_pc;
    logic          [31:2] next_seq_pc_reg;
    logic                 stalling;
    logic                 fetched;
    logic                 prefetch_wr_en;
    logic                 resteer;
    logic                 icache_valid_next;
    logic                 icache_busy_start;
    logic                 fetched_next;
    logic                 resteer_pending;
    logic                 resteer_pending_next;
    logic          [31:2] resteer_target;
    logic          [31:2] resteer_target_next;
    fetch_packet          prefetch_packet_in;
    fetch_packet          prefetch_packet_out;
    logic                 prefetch_rd_en;
    logic                 prefetch_empty;
    logic                 prefetch_full;
    logic                 prefetch_nearly_full;
    rxv_prediction        prediction_reg;
    logic                 prefetch_flush;
    logic                 fetch_idle_next;
    logic                 tlb_stalling;
    logic                 tlb_stalling_next;
    logic                 page_fault;
    logic                 icache_busy_start_next;

    function logic tlb_access_okay;
        begin
            tlb_access_okay = 1'b1;

            // Invalid PTE
            if (!fetch_translation.valid) tlb_access_okay = 1'b0;
            // PTE not accessed
            if (!fetch_translation.accessed) tlb_access_okay = 1'b0;
            // Page not accessible
            if (!fetch_translation.exec) tlb_access_okay = 1'b0;
            // User access to supervisor page
            if (effective_privilege(
                    mstatus, current_privilege
                ) == RXVCSR::PRIV_U && !fetch_translation.user)
                tlb_access_okay = 1'b0;
        end
    endfunction

    PosedgeDetect ICacheBusyStart (
        .clk  (clk),
        .reset(reset),
        .d    (icache_busy_start_next),
        .q    (icache_busy_start)
    );

    Fifo #(
        .data_width        ($bits(fetch_packet)),
        .order             (3),
        .nearly_full_thresh(4)
    ) prefetch_fifo (
        .clk        (clk),
        .reset      (reset),
        .flush      (prefetch_flush),
        .wr_en      (prefetch_wr_en),
        .wr_data    (prefetch_packet_in),
        // verilator lint_off PINCONNECTEMPTY
        .wr_ptr     (),
        // verilator lint_on PINCONNECTEMPTY
        .rd_en      (prefetch_rd_en),
        .rd_data    (prefetch_packet_out),
        // verilator lint_off PINCONNECTEMPTY
        .rd_ptr     (),
        // verilator lint_on PINCONNECTEMPTY
        .empty      (prefetch_empty),
        .full       (prefetch_full),
        .nearly_full(prefetch_nearly_full)
    );

    RXVAssert prefetch_no_write_full (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(prefetch_full && prefetch_wr_en))
    );

    RXVAssert prefetch_phys_offset (
        .clk      (clk),
        .en       (prefetch_wr_en),
        .condition(fetched_pc[11:2] == icache_phys[11:2])
    );

    always_comb begin
        decode_valid      = ~prefetch_empty;
        decode_pc         = prefetch_packet_out.pc;
        decode_next_pc    = prefetch_packet_out.next_pc;
        decode_instr      = prefetch_packet_out.instr;
        decode_prediction = prefetch_packet_out.prediction;
        decode_page_fault = decode_valid & prefetch_packet_out.page_fault;
`ifdef RXV_TRACE
        decode_phys = prefetch_packet_out.phys;
`endif  // RXV_TRACE
    end

    always_comb begin
        tlb_stalling_next = fetch_tlb_busy;
    end

    always_comb begin
        icache_busy_start_next = icache_busy | fetch_tlb_busy;
    end

    always_comb begin
        page_fault = ((fetched && !fetch_tlb_busy) ||
                      (tlb_stalling && !fetch_tlb_busy)) && !tlb_access_okay();
    end

    always_comb begin
        prefetch_packet_in.pc         = fetched_pc;
        prefetch_packet_in.next_pc    = next_seq_pc_reg;
        prefetch_packet_in.instr      = icache_instr;
        prefetch_packet_in.prediction = prediction_reg;
        prefetch_packet_in.page_fault = page_fault;
`ifdef RXV_TRACE
        prefetch_packet_in.phys = icache_phys[31:12];
`endif  // RXV_TRACE
    end

    always_comb begin
        prefetch_rd_en = ~prefetch_empty & ~decode_fe_stall;
    end

    always_comb begin
        prefetch_flush = resteer | exception_pending | except_valid;
    end

    always_comb begin
        fetched_next = icache_valid & ~icache_busy & ~fetch_tlb_busy & ~resteer &
            ~exception_pending & ~except_valid & ~resteer_pending &
            ~global_stall_active;
    end

    always_comb begin
        stalling = icache_busy | fetch_tlb_busy | global_stall_active;
    end

    always_comb begin
        prefetch_wr_en = (fetched | page_fault) & ~stalling & ~resteer & ~resteer_pending &
            ~exception_pending & ~except_valid & ~global_stall_active;
    end

    always_comb begin
        resteer = exception_resteer | exec_resteer | decode_resteer;
    end

    always_comb begin
        branch_predict_address = next_pc;
    end

    always_comb begin
        icache_valid_next = ~prefetch_nearly_full & ~global_stall_active &
            ~exception_pending & ~except_valid & ~irq_pending & ~page_fault &
            ~fetch_tlb_busy & ~icache_busy;
    end

    always_comb begin
        icache_phys       = {fetch_translation.pa, fetched_pc[11:2]};
        icache_phys_valid = fetched & fetch_translation.valid & ~fetch_tlb_busy & ~page_fault;
    end

    always_comb begin
        next_seq_pc = pc + 1'b1;
        next_pc     = !icache_busy && !fetch_tlb_busy && icache_valid ? next_seq_pc : pc;

        if (prefetch_nearly_full && !icache_busy && !fetch_tlb_busy)
            next_pc = icache_valid ? next_seq_pc : pc;
        if (icache_busy_start) next_pc = fetched_pc;
        if (icache_valid && prediction.predicted && prediction.predict_taken &&
            !icache_busy && !fetch_tlb_busy)
            next_pc = prediction.prediction;
        if (resteer_pending) next_pc = resteer_target;
        if (decode_resteer) next_pc = decode_resteer_tgt;
        if (exec_resteer) next_pc = exec_resteer_tgt;
        if (exception_resteer) next_pc = exception_resteer_tgt;
    end

    always_comb begin
        fetched_pc_next = icache_address;
        if (icache_busy || fetch_tlb_busy) fetched_pc_next = fetched_pc;
    end

    always_comb begin
        irq_epc = pc;
    end

    always_comb begin
        resteer_target_next = resteer_target;
        if (decode_resteer) resteer_target_next = decode_resteer_tgt;
        if (exec_resteer) resteer_target_next = exec_resteer_tgt;
        if (exception_resteer) resteer_target_next = exception_resteer_tgt;
    end

    always_comb begin
        resteer_pending_next = resteer_pending;
        if (~icache_busy && ~fetch_tlb_busy) resteer_pending_next = 1'b0;
        if (resteer) resteer_pending_next = 1'b1;
    end

    always_comb begin
        fetch_idle_next = prefetch_empty & ~icache_valid & ~fetched & ~icache_busy &
            ~fetch_tlb_busy & ~resteer_pending & ~exec_resteer;
    end

    always_comb begin
        fetch_tlb_valid = icache_valid & ~icache_busy;
    end

    RXVDFF #(
        .width    (30),
        .reset_val(reset_address[31:2])
    ) pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_pc),
        .q    (pc)
    );

    RXVDFF #(
        .width(30)
    ) icache_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_pc),
        .q    (icache_address)
    );

    RXVDFF icache_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (icache_valid_next),
        .q    (icache_valid)
    );

    RXVDFF #(
        .width(30)
    ) fetched_pc_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fetched_pc_next),
        .q    (fetched_pc)
    );

    RXVDFF #(
        .width(30)
    ) next_seq_pc_reg_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_seq_pc),
        .q    (next_seq_pc_reg)
    );

    RXVDFF resteer_pending_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (resteer_pending_next),
        .q    (resteer_pending)
    );

    RXVDFF #(
        .width(30)
    ) resteer_target_dff (
        .clk  (clk),
        .reset(reset),
        .en   (resteer),
        .d    (resteer_target_next),
        .q    (resteer_target)
    );

    RXVDFF #(
        .width($bits(RXVTypes::rxv_prediction))
    ) decode_prediction_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (prediction),
        .q    (prediction_reg)
    );

    RXVDFF fetched_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fetched_next),
        .q    (fetched)
    );

    RXVDFF fetch_idle_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fetch_idle_next),
        .q    (fetch_idle)
    );

    RXVDFF tlb_stalling_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (tlb_stalling_next),
        .q    (tlb_stalling)
    );

endmodule
