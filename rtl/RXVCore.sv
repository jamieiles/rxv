`default_nettype none

import RXVTypes::arch_reg_tag;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::commit_entry;
import RXVTypes::num_phys_regs;
import RXVTypes::rxv_prediction;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_alu_op;
import RXVTypes::rxv_uop;
import RXVTrace::trace_write_reg;

module RXVCore #(
    parameter int          icache_nr_lines        = 16,
    parameter int          icache_nr_ways         = 4,
    parameter int          icache_line_size_bytes = 32,
    parameter int          dcache_nr_lines        = 16,
    parameter int          dcache_nr_ways         = 4,
    parameter int          dcache_line_size_bytes = 32,
    parameter int          btb_num_entries        = 256,
    parameter int          btb_tag_bits           = 10,
    parameter int          commit_order           = 4,
    parameter logic [31:0] reset_address          = 32'h80000000
) (
    input logic                clk,
    input logic                reset,
    // Instruction bus
          MemInterface.Manager instruction_bus,
          MemInterface.Manager data_bus
);

    localparam int commit_num_entries = (1 << commit_order);
    localparam int commit_width = $clog2(commit_num_entries);

    logic          [             31:2] icache_address;
    logic                              icache_valid;
    logic                              icache_busy;
    logic          [             31:0] icache_dout;
    logic                              icache_invalidate;

    logic          [             31:2] fetch_predict_address;
    rxv_prediction                     fetch_prediction;

    logic                              decode_resteer;
    logic          [             31:2] decode_resteer_tgt;
    logic                              decode_stall;
    logic          [             31:2] decode_resume_tgt;
    logic                              decode_valid;
    logic          [             31:2] decode_pc;
    logic          [             31:2] decode_next_pc;
    rxv_prediction                     decode_prediction;
    logic          [             31:0] decode_instr;
    logic                              decode_predict_kill;
    logic          [             31:2] decode_kill_address;
    logic          [             31:1] exec_branch_target;

    logic                              exec_resteer;
    logic          [             31:2] exec_resteer_tgt;
    logic                              exec_predict_update;
    logic          [              1:0] exec_predict_prev_strength;
    logic                              exec_update_predict_taken;
    logic          [             31:2] exec_update_predict_address;
    logic          [             31:2] exec_update_predict_target;
    logic          [             31:0] exec_immed;
    rxv_opcode                         exec_opcode;
    rxv_uop                            exec_uop;
    logic                              exec_bypass_rs1;
    logic                              exec_bypass_rs2;

    rxv_alu_op                         exec_alu_op;
    logic                              exec_valid;
    logic                              exec_have_writeback;
    phys_reg_tag                       exec_rd;
    logic          [ commit_width-1:0] exec_id;
    logic          [             31:2] exec_pc;
    logic          [             31:2] exec_next_pc;
    rxv_prediction                     exec_prediction;

    phys_reg_tag                       rd_addr_a;
    phys_reg_tag                       rd_addr_b;
    logic          [             31:0] rd_data_a;
    logic          [             31:0] rd_data_b;
    logic                              reg_wr_en;
    phys_reg_tag                       reg_wr_addr;
    logic          [             31:0] reg_wr_data;
    logic          [             31:0] rs1_data;
    logic          [             31:0] rs2_data;

    renamed_reg                        rename_in;
    logic                              rename_valid;
    phys_reg_tag                       stale_phys_reg;
    logic                              commit_valid;
    logic                              rename_rollback;
    arch_reg_tag                       lookup_tag_in               [1:0];
    phys_reg_tag                       lookup_tag_out              [1:0];

    logic                              reg_alloc_empty;
    logic                              reg_alloc;
    logic                              reg_free;
    phys_reg_tag                       reg_alloc_phys;
    phys_reg_tag                       reg_free_phys;

    // verilator lint_off UNUSED
    logic          [             31:2] dcache_address;
    logic                              dcache_valid;
    logic                              dcache_busy;
    logic          [             31:0] dcache_din;
    logic                              dcache_wren;
    logic          [              3:0] dcache_bytesel;
    logic          [             31:0] dcache_dout;
    logic                              dcache_invalidate;
    logic                              dcache_clean;
    logic          [             31:0] dcache_phys_out;
    logic                              dcache_device_memory;
    // verilator lint_on UNUSED

    logic                              commit_full;
    commit_entry                       dispatch_in;
    logic                              dispatch_valid;
    logic          [ commit_width-1:0] dispatch_id;
    logic                              kill_valid;
    logic          [ commit_width-1:0] complete_id;
    logic                              complete_valid;
    logic          [ commit_width-1:0] except_id;
    logic                              except_valid;
    logic                              commit_empty;
    commit_entry                       commit_out;
    logic                              commit_complete_out;
    logic                              commit_killed_out;
    logic                              commit_excepted_out;
    renamed_reg                        commit_rename_out;
    logic                              commit_rename_valid;
    logic          [ commit_width-1:0] commit_id;

    phys_reg_tag                       busy_reg_in;
    logic                              busy_valid_in;
    logic          [num_phys_regs-1:0] scoreboard_busy;

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
        .prediction                (fetch_prediction),
        .decode_predict_kill       (decode_predict_kill),
        .decode_kill_address       (decode_kill_address),
        .exec_predict_update       (exec_predict_update),
        .exec_predict_prev_strength(exec_predict_prev_strength),
        .exec_predict_taken        (exec_update_predict_taken),
        .exec_predict_address      (exec_update_predict_address),
        .exec_predict_target       (exec_update_predict_target)
    );

    RXVFetch #(
        .reset_address(reset_address)
    ) RXVFetch (
        .clk                   (clk),
        .reset                 (reset),
        .icache_address        (icache_address),
        .icache_valid          (icache_valid),
        .icache_busy           (icache_busy),
        .icache_instr          (icache_dout),
        .branch_predict_address(fetch_predict_address),
        .prediction            (fetch_prediction),
        .decode_resteer        (decode_resteer),
        .decode_resteer_tgt    (decode_resteer_tgt),
        .decode_stall          (decode_stall),
        .decode_resume_tgt     (decode_resume_tgt),
        .decode_valid          (decode_valid),
        .decode_pc             (decode_pc),
        .decode_next_pc        (decode_next_pc),
        .decode_prediction     (decode_prediction),
        .decode_instr          (decode_instr),
        .exec_resteer          (exec_resteer),
        .exec_resteer_tgt      (exec_resteer_tgt)
    );

    RXVDecode #(
        .commit_order(commit_order)
    ) RXVDecode (
        .clk                        (clk),
        .reset                      (reset),
        .decode_valid               (decode_valid),
        .decode_pc                  (decode_pc),
        .decode_next_pc             (decode_next_pc),
        .decode_prediction          (decode_prediction),
        .decode_instr               (decode_instr),
        .decode_predict_kill        (decode_predict_kill),
        .decode_predict_kill_address(decode_kill_address),
        .decode_resteer             (decode_resteer),
        .decode_resteer_tgt         (decode_resteer_tgt),
        .decode_stall               (decode_stall),
        .decode_resume_tgt          (decode_resume_tgt),
        .reg_wr_addr                (reg_wr_addr),
        .reg_wr_en                  (reg_wr_en),
        .reg_alloc_empty            (reg_alloc_empty),
        .reg_alloc_valid            (reg_alloc),
        .allocated_reg              (reg_alloc_phys),
        .commit_buffer_full         (commit_full),
        .commit_buffer_empty        (commit_empty),
        .commit_dispatch            (dispatch_in),
        .commit_dispatch_valid      (dispatch_valid),
        .dispatch_id                (dispatch_id),
        .busy_reg_out               (busy_reg_in),
        .busy_valid_out             (busy_valid_in),
        .busy_status                (scoreboard_busy),
        .rename_out                 (rename_in),
        .rename_out_valid           (rename_valid),
        .stale_phys_reg             (stale_phys_reg),
        .rename_lookup_arch         (lookup_tag_in),
        .rename_lookup_phys         (lookup_tag_out),
        .ra_phys                    (rd_addr_a),
        .rb_phys                    (rd_addr_b),
        .exec_alu_op                (exec_alu_op),
        .exec_valid                 (exec_valid),
        .exec_have_writeback        (exec_have_writeback),
        .exec_rd                    (exec_rd),
        .exec_id                    (exec_id),
        .exec_immed                 (exec_immed),
        .exec_opcode                (exec_opcode),
        .exec_uop                   (exec_uop),
        .exec_bypass_rs1            (exec_bypass_rs1),
        .exec_bypass_rs2            (exec_bypass_rs2),
        .exec_pc                    (exec_pc),
        .exec_next_pc               (exec_next_pc),
        .exec_prediction            (exec_prediction),
        .exec_branch_target         (exec_branch_target),
        .kill_valid                 (kill_valid)
    );

    RXVIntExec #(
        .commit_order(commit_order)
    ) RXVIntExec (
        .clk                        (clk),
        .reset                      (reset),
        .kill_valid                 (kill_valid),
        .exec_valid                 (exec_valid),
        .exec_alu_op                (exec_alu_op),
        .exec_have_writeback        (exec_have_writeback),
        .exec_rd                    (exec_rd),
        .exec_id                    (exec_id),
        .op1                        (rs1_data),
        .op2                        (rs2_data),
        .exec_reg_addr              (reg_wr_addr),
        .exec_reg_wr_en             (reg_wr_en),
        .exec_reg_wr_data           (reg_wr_data),
        .exec_complete              (complete_valid),
        .exec_complete_id           (complete_id),
        .exec_immed                 (exec_immed),
        .exec_opcode                (exec_opcode),
        .exec_branch_target         (exec_branch_target),
        .exec_uop                   (exec_uop),
        .exec_pc                    (exec_pc),
        .exec_next_pc               (exec_next_pc),
        .exec_prediction            (exec_prediction),
        .exec_predict_update        (exec_predict_update),
        .exec_predict_prev_strength (exec_predict_prev_strength),
        .exec_update_predict_taken  (exec_update_predict_taken),
        .exec_update_predict_address(exec_update_predict_address),
        .exec_update_predict_target (exec_update_predict_target),
        .exec_resteer               (exec_resteer),
        .exec_resteer_tgt           (exec_resteer_tgt)
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
        .commit_valid  (commit_rename_valid),
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

    RXVCommitBuffer #(
        .order(commit_order)
    ) RXVCommitBuffer (
        .clk                (clk),
        .reset              (reset),
        .full               (commit_full),
        .dispatch_in        (dispatch_in),
        .dispatch_valid     (dispatch_valid),
        .dispatch_id        (dispatch_id),
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
        .commit_valid       (commit_valid),
        .commit_id          (commit_id)
    );

    RXVScoreboard RXVScoreboard (
        .clk               (clk),
        .reset             (reset),
        .busy_reg_in       (busy_reg_in),
        .busy_valid_in     (busy_valid_in),
        .kill_reg_in       (reg_free_phys),
        .kill_valid_in     (reg_free),
        .writeback_reg_in  (reg_wr_addr),
        .writeback_valid_in(reg_wr_en),
        .busy_out          (scoreboard_busy)
    );

    RXVCommitter #(
        .commit_order(commit_order)
    ) RXVCommitter (
        .clk                   (clk),
        .commit_empty          (commit_empty),
        .commit_in             (commit_out),
        .commit_complete       (commit_complete_out),
        .commit_killed         (commit_killed_out),
        .commit_excepted       (commit_excepted_out),
        .commit_valid          (commit_valid),
        .commit_id             (commit_id),
        .commit_rename_out     (commit_rename_out),
        .commit_rename_valid   (commit_rename_valid),
        .commit_rename_rollback(rename_rollback),
        .commit_reg_push       (reg_free),
        .commit_reg_reg        (reg_free_phys)
    );

    always_comb begin
        icache_invalidate    = 'b0;
        dcache_address       = 'b0;
        dcache_wren          = 'b0;
        dcache_bytesel       = 'b0;
        dcache_invalidate    = 'b0;
        dcache_clean         = 'b0;
        dcache_device_memory = 'b0;
        dcache_valid         = 'b0;
        dcache_din           = 'b0;
        except_id            = 'b0;
        except_valid         = 'b0;
    end

    always_comb begin
        rs1_data = exec_bypass_rs1 ? reg_wr_data : rd_data_a;
        rs2_data = exec_bypass_rs2 ? reg_wr_data : rd_data_b;
    end

    always_comb begin
        kill_valid = exec_valid & exec_resteer;
    end

`ifdef verilator
    `include "RXVTrace_cpp.svh"

    always_ff @(posedge clk) begin
        if (reg_wr_en && |reg_wr_addr) begin
            // verilator lint_off UNUSED
            commit_entry ce = RXVCommitBuffer.commit_fifo.mem[complete_id];
            // verilator lint_on UNUSED
            trace_write_reg(32'(complete_id), ce.dest_reg.arch, reg_wr_data);
        end
    end
`endif  // verilator

endmodule
