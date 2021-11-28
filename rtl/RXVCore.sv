`default_nettype none

import RXVTypes::arch_reg_tag;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::commit_entry;
import RXVTypes::num_phys_regs;

module RXVCore #(
    parameter int          icache_nr_lines        = 16,
    parameter int          icache_nr_ways         = 4,
    parameter int          icache_line_size_bytes = 32,
    parameter int          dcache_nr_lines        = 16,
    parameter int          dcache_nr_ways         = 4,
    parameter int          dcache_line_size_bytes = 32,
    parameter int          btb_num_entries        = 256,
    parameter int          btb_tag_bits           = 10,
    parameter logic [31:0] reset_address          = 32'h80000000
) (
    input logic                clk,
    input logic                reset,
    // Instruction bus
          MemInterface.Manager instruction_bus,
          MemInterface.Manager data_bus
);

    logic        [             31:2] icache_address;
    logic                            icache_valid;
    logic                            icache_busy;
    logic        [             31:0] icache_dout;
    logic                            icache_invalidate;

    logic        [             31:2] fetch_predict_address;
    logic                            fetch_predict_valid;
    logic        [             31:2] fetch_prediction;
    logic                            fetch_predict_taken;
    logic        [              1:0] fetch_predict_strength;

    logic                            decode_resteer;
    logic        [             31:2] decode_resteer_tgt;
    logic                            decode_stall;
    logic        [             31:2] decode_resume_tgt;
    logic                            decode_valid;
    logic        [             31:2] decode_pc;
    logic        [             31:2] decode_next_pc;
    logic        [             31:0] decode_instr;
    logic                            decode_predicted;
    logic                            decode_predict_taken;
    logic        [              1:0] decode_predict_strength;
    logic                            decode_predict_kill;
    logic        [             31:2] decode_kill_address;

    logic                            exec_resteer;
    logic        [             31:2] exec_resteer_tgt;
    logic                            exec_predict_update;
    logic        [              1:0] exec_predict_prev_strength;
    logic                            exec_predict_taken;
    logic        [             31:2] exec_predict_address;
    logic        [             31:2] exec_predict_target;

    phys_reg_tag                     rd_addr_a;
    phys_reg_tag                     rd_addr_b;
    logic        [             31:0] rd_data_a;
    logic        [             31:0] rd_data_b;
    logic                            reg_wr_en;
    phys_reg_tag                     reg_wr_addr;
    logic        [             31:0] reg_wr_data;

    renamed_reg                      rename_in;
    logic                            rename_valid;
    phys_reg_tag                     stale_phys_reg;
    logic                            commit_valid;
    logic                            rename_rollback;
    arch_reg_tag                     lookup_tag_in              [1:0];
    phys_reg_tag                     lookup_tag_out             [1:0];

    logic                            reg_alloc_empty;
    logic                            reg_alloc;
    logic                            reg_free;
    phys_reg_tag                     reg_alloc_phys;
    phys_reg_tag                     reg_free_phys;

    logic        [             31:2] dcache_address;
    logic                            dcache_valid;
    logic                            dcache_busy;
    logic        [             31:0] dcache_din;
    logic                            dcache_wren;
    logic        [              3:0] dcache_bytesel;
    logic        [             31:0] dcache_dout;
    logic                            dcache_invalidate;
    logic                            dcache_clean;
    logic        [             31:0] dcache_phys_out;
    logic                            dcache_device_memory;

    logic                            commit_full;
    commit_entry                     dispatch_in;
    logic                            dispatch_valid;
    logic        [              2:0] dispatch_id;
    logic        [              2:0] kill_id;
    logic                            kill_valid;
    logic        [              2:0] complete_id;
    logic                            complete_valid;
    logic        [              2:0] except_id;
    logic                            except_valid;
    logic                            commit_empty;
    commit_entry                     commit_out;
    logic                            commit_complete_out;
    logic                            commit_killed_out;
    logic                            commit_excepted_out;
    renamed_reg commit_rename_out;

    phys_reg_tag                     busy_reg_in;
    logic                            busy_valid_in;
    phys_reg_tag                     kill_reg_in;
    logic                            kill_valid_in;
    logic        [num_phys_regs-1:0] scoreboard_busy;

    RXVICache #(
        .nr_lines       (icache_nr_lines),
        .nr_ways        (icache_nr_ways),
        .line_size_bytes(icache_line_size_bytes)
    ) RXVICache (
        .clk       (clk),
        .reset     (reset),
        .bus       (instruction_bus),
        .address   (icache_address),
        .valid     (icache_valid),
        .busy      (icache_busy),
        .dout      (icache_dout),
        .invalidate(icache_invalidate)
    );

    RXVBranchPredictor #(
        .num_entries(btb_num_entries),
        .tag_bits   (btb_tag_bits)
    ) RXVBranchPredictor (
        .clk                       (clk),
        .reset                     (reset),
        .fetch_address             (fetch_predict_address),
        .fetch_prediction_valid    (fetch_predict_valid),
        .fetch_prediction          (fetch_prediction),
        .fetch_predict_taken       (fetch_predict_taken),
        .fetch_predict_strength    (fetch_predict_strength),
        .decode_predict_kill       (decode_predict_kill),
        .decode_kill_address       (decode_kill_address),
        .exec_predict_update       (exec_predict_update),
        .exec_predict_prev_strength(exec_predict_prev_strength),
        .exec_predict_taken        (exec_predict_taken),
        .exec_predict_address      (exec_predict_address),
        .exec_predict_target       (exec_predict_target)
    );

    RXVFetch #(
        .reset_address(reset_address)
    ) RXVFetch (
        .clk                    (clk),
        .reset                  (reset),
        .icache_address         (icache_address),
        .icache_valid           (icache_valid),
        .icache_busy            (icache_busy),
        .icache_instr           (icache_dout),
        .branch_predict_address (fetch_predict_address),
        .branch_predict_valid   (fetch_predict_valid),
        .branch_prediction      (fetch_prediction),
        .branch_predict_taken   (fetch_predict_taken),
        .branch_predict_strength(fetch_predict_strength),
        .decode_resteer         (decode_resteer),
        .decode_resteer_tgt     (decode_resteer_tgt),
        .decode_stall           (decode_stall),
        .decode_resume_tgt      (decode_resume_tgt),
        .decode_valid           (decode_valid),
        .decode_pc              (decode_pc),
        .decode_next_pc         (decode_next_pc),
        .decode_instr           (decode_instr),
        .decode_predicted       (decode_predicted),
        .decode_predict_taken   (decode_predict_taken),
        .decode_predict_strength(decode_predict_strength),
        .exec_resteer           (exec_resteer),
        .exec_resteer_tgt       (exec_resteer_tgt)
    );

    RXVRegisterFile RXVRegisterFile (
        .clk      (clk),
        .reset    (reset),
        .rd_addr_a(rd_addr_a),
        .rd_data_a(rd_data_a),
        .rd_addr_b(rd_addr_b),
        .rd_data_b(rd_data_b),
        .wr_en    (reg_wr_en),
        .wr_addr  (reg_wr_addr),
        .wr_data  (reg_wr_data)
    );

    RXVRenameFile RXVRenameFile (
        .clk           (clk),
        .reset         (reset),
        .rename_in     (rename_in),
        .rename_valid  (rename_valid),
        .stale_phys_reg(stale_phys_reg),
        .lookup_tag_in (lookup_tag_in),
        .lookup_tag_out(lookup_tag_out),
        .commit_in     (commit_rename_out),
        .commit_valid  (commit_valid),
        .rollback      (rename_rollback)
    );

    RXVRegisterAllocator #(
        .num_regs(num_phys_regs)
    ) RXVRegisterAllocator (
        .clk     (clk),
        .reset   (reset),
        .empty   (reg_alloc_empty),
        .pop     (reg_alloc),
        .pop_reg (reg_alloc_phys),
        .push    (reg_free),
        .push_reg(reg_free_phys)
    );

    RXVDCache #(
        .nr_lines       (dcache_nr_lines),
        .nr_ways        (dcache_nr_ways),
        .line_size_bytes(dcache_line_size_bytes)
    ) RXVDCache (
        .clk          (clk),
        .reset        (reset),
        .bus          (data_bus),
        .address      (dcache_address),
        .valid        (dcache_valid),
        .busy         (dcache_busy),
        .din          (dcache_din),
        .wren         (dcache_wren),
        .bytesel      (dcache_bytesel),
        .clean        (dcache_clean),
        .phys_out     (dcache_phys_out),
        .device_memory(dcache_device_memory),
        .dout         (dcache_dout),
        .invalidate   (dcache_invalidate)
    );

    RXVCommitBuffer RXVCommitBuffer (
        .clk                (clk),
        .reset              (reset),
        .full               (commit_full),
        .dispatch_in        (dispatch_in),
        .dispatch_valid     (dispatch_valid),
        .dispatch_id        (dispatch_id),
        .kill_id            (kill_id),
        .kill_valid         (kill_valid),
        .complete_id        (complete_id),
        .complete_valid     (complete_valid),
        .except_id          (except_id),
        .except_valid       (except_valid),
        .empty              (commit_empty),
        .commit_out         (commit_out),
        .commit_complete_out(commit_complete_out),
        .commit_killed_out  (commit_killed_out),
        .commit_excepted_out(commit_excepted_out),
        .commit_valid       (commit_valid)
    );

    RXVScoreboard RXVScoreboard (
        .clk               (clk),
        .reset             (reset),
        .busy_reg_in       (busy_reg_in),
        .busy_valid_in     (busy_valid_in),
        .kill_reg_in       (kill_reg_in),
        .kill_valid_in     (kill_valid_in),
        .writeback_reg_in  (reg_wr_addr),
        .writeback_valid_in(reg_wr_en),
        .busy_out          (scoreboard_busy)
    );

    RXVCommitter RXVCommitter (
        .clk                   (clk),
        .commit_empty          (commit_empty),
        .commit_in             (commit_out),
        .commit_complete       (commit_complete_out),
        .commit_killed         (commit_killed_out),
        .commit_excepted       (commit_excepted_out),
        .commit_valid          (commit_valid),
        .commit_rename_out     (commit_rename_out),
        .commit_rename_valid   (commit_valid),
        .commit_rename_rollback(rename_rollback),
        .commit_reg_push       (reg_free),
        .commit_reg_reg        (reg_free_phys)
    );

    always_comb begin
        icache_invalidate          = 'b0;
        decode_resteer             = 'b0;
        decode_resteer_tgt         = 'b0;
        decode_stall               = 'b0;
        decode_resume_tgt          = 'b0;
        decode_predict_kill        = 'b0;
        decode_kill_address        = 'b0;
        exec_resteer               = 'b0;
        exec_resteer_tgt           = 'b0;
        exec_predict_update        = 'b0;
        exec_predict_prev_strength = 'b0;
        exec_predict_taken         = 'b0;
        exec_predict_address       = 'b0;
        exec_predict_target        = 'b0;
        reg_wr_addr                = 'b0;
        reg_wr_data                = 'b0;
        reg_wr_en                  = 'b0;
        rename_in                  = 'b0;
        rename_valid               = 'b0;
        lookup_tag_in[0]           = 'b0;
        lookup_tag_in[1]           = 'b0;
        reg_alloc                  = 'b0;
        dcache_address             = 'b0;
        dcache_wren                = 'b0;
        dcache_bytesel             = 'b0;
        dcache_invalidate          = 'b0;
        dcache_clean               = 'b0;
        dcache_device_memory       = 'b0;
        dcache_valid               = 'b0;
        dcache_din                 = 'b0;
        dispatch_in                = 'b0;
        dispatch_valid             = 'b0;
        kill_id                    = 'b0;
        kill_valid                 = 'b0;
        complete_id                = 'b0;
        complete_valid             = 'b0;
        except_id                  = 'b0;
        except_valid               = 'b0;
        busy_reg_in                = 'b0;
        busy_valid_in              = 'b0;
        kill_reg_in                = 'b0;
        kill_valid_in              = 'b0;
    end

    always_comb begin
        rd_addr_a = lookup_tag_out[0];
        rd_addr_b = lookup_tag_out[1];
    end

endmodule
