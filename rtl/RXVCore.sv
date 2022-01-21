`default_nettype none

import RXVTypes::arch_reg_tag;
import RXVTypes::phys_reg_tag;
import RXVTypes::renamed_reg;
import RXVTypes::commit_entry;
import RXVTypes::num_phys_regs;
import RXVTypes::rxv_prediction;
import RXVTypes::rxv_opcode;
import RXVTypes::rxv_alu_op;
import RXVTypes::rxv_csr_op;
import RXVTypes::rxv_uop;
import RXVTrace::trace_write_reg;
import RXVTrace::trace_write_csr;
import RXVCSR::RXVException;
import RXVCSR::mtvec;
import RXVCSR::mcause;

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
    parameter int          banked_register_file   = 0,
    parameter logic [31:0] reset_address          = 32'h80000000,
    parameter logic [31:0] vendorid               = 0,
    parameter logic [31:0] archid                 = 0,
    parameter logic [31:0] impid                  = 0,
    parameter logic [31:0] device_base            = 32'hf0000000,
    parameter logic [31:0] device_end             = 32'hffffffff
) (
    input logic                clk,
    input logic                reset,
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

    logic                              dispatch_int;
    logic                              dispatch_lsu;
    logic                              dispatch_mul;
    logic                              int_ready;
    logic                              lsu_ready;
    logic                              mul_ready;

    logic                              decode_resteer;
    logic          [             31:2] decode_resteer_tgt;
    logic                              decode_stall;
    logic                              decode_valid;
    logic          [             31:2] decode_pc;
    logic          [             31:2] decode_next_pc;
    rxv_prediction                     decode_prediction;
    logic          [             31:0] decode_instr;
    logic                              decode_predict_kill;
    logic          [             31:2] decode_kill_address;
    logic          [             31:1] exec_branch_target;
    logic          [             11:0] decode_csr_addr;
    logic                              decode_valid_csr;
    RXVException                       decode_exception;
    logic          [ commit_width-1:0] decode_except_id;

    logic                              exec_resteer;
    logic          [             31:2] exec_resteer_tgt;
    logic                              int_exec_resteer;
    logic          [             31:2] int_exec_resteer_tgt;
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
    logic          [             31:0] exec_csr_rd_data;
    logic          [             11:0] exec_csr_wr_addr;
    logic          [             31:0] exec_csr_wr_data;
    logic                              exec_csr_wr_en;
    logic          [             31:2] mepc_val;
    RXVException                       exec_exception;
    logic          [ commit_width-1:0] exec_except_id;
    logic          [ commit_width-1:0] int_exec_complete_id;
    logic                              int_exec_complete_valid;
    logic                              int_exec_reg_wr_en;
    phys_reg_tag                       int_exec_reg_wr_addr;
    logic          [             31:0] int_exec_reg_wr_data;

    logic                              int_complete_valid;
    logic          [ commit_width-1:0] int_complete_id;

    rxv_alu_op                         exec_alu_op;
    rxv_csr_op                         exec_csr_op;
    logic                              int_exec_valid;
    logic                              exec_have_writeback;
    phys_reg_tag                       exec_rd;
    logic          [ commit_width-1:0] exec_id;
    logic          [             31:2] exec_pc;
    logic          [             31:2] exec_next_pc;
    rxv_prediction                     exec_prediction;

    logic                              lsu_exec_valid;
    logic                              lsu_busy;
    RXVException                       lsu_exception;
    logic          [ commit_width-1:0] lsu_except_id;
    logic                              lsu_resteer;
    logic          [             31:2] lsu_resteer_tgt;

    logic                              mul_exec_valid;
    logic          [ commit_width-1:0] mul_exec_complete_id;
    logic                              mul_exec_complete_valid;
    logic                              mul_exec_reg_wr_en;
    phys_reg_tag                       mul_exec_reg_wr_addr;
    logic          [             31:0] mul_exec_reg_wr_data;

    logic          [ commit_width-1:0] lsu_complete_id;
    logic                              lsu_complete_valid;
    logic                              lsu_reg_wr_en;
    phys_reg_tag                       lsu_reg_wr_addr;
    logic          [             31:0] lsu_reg_wr_data;
    logic                              lsu_reg_busy;
    logic                              lsu_busy_kill;
    logic                              lsu_global_stall_start;
    logic                              lsu_global_stall_end;

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

    logic                              commit_full;
    commit_entry                       dispatch_in;
    logic                              dispatch_valid;
    logic          [ commit_width-1:0] dispatch_id;
    logic                              kill_valid;
    logic                              resteer_kill_valid;
    logic          [ commit_width-1:0] except_id;
    logic                              except_valid;
    logic                              exception_pending;
    logic                              global_stall_active;
    logic                              commit_empty;
    commit_entry                       commit_out;
    logic                              commit_complete_out;
    logic                              commit_killed_out;
    logic                              commit_excepted_out;
    renamed_reg                        commit_rename_out;
    logic                              commit_rename_valid;
    logic          [ commit_width-1:0] commit_id;
    logic                              retired;
    logic                              exception_resteer;
    logic          [             31:2] exception_resteer_tgt;
    mtvec                              mtvec_val;
    mcause                             mcause_val;

    phys_reg_tag                       busy_reg_in;
    logic                              busy_valid_in;
    logic          [num_phys_regs-1:0] scoreboard_busy;

    logic                              pmu_cyclesh_wren;
    logic                              pmu_cyclesl_wren;
    logic                              pmu_instreth_wren;
    logic                              pmu_instretl_wren;
    logic          [             63:0] pmu_cycles;
    logic          [             63:0] pmu_instret;

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
        .except_valid          (except_valid),
        .exception_pending     (exception_pending),
        .global_stall_active   (global_stall_active),
        .icache_address        (icache_address),
        .icache_valid          (icache_valid),
        .icache_busy           (icache_busy),
        .icache_instr          (icache_dout),
        .branch_predict_address(fetch_predict_address),
        .prediction            (fetch_prediction),
        .decode_resteer        (decode_resteer),
        .decode_resteer_tgt    (decode_resteer_tgt),
        .decode_stall          (decode_stall),
        .decode_valid          (decode_valid),
        .decode_pc             (decode_pc),
        .decode_next_pc        (decode_next_pc),
        .decode_prediction     (decode_prediction),
        .decode_instr          (decode_instr),
        .exec_resteer          (exec_resteer),
        .exec_resteer_tgt      (exec_resteer_tgt),
        .exception_resteer     (exception_resteer),
        .exception_resteer_tgt (exception_resteer_tgt)
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
        .decode_csr_addr            (decode_csr_addr),
        .valid_csr_in               (decode_valid_csr),
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
        .int_ready                  (int_ready),
        .lsu_ready                  (lsu_ready),
        .mul_ready                  (mul_ready),
        .dispatch_int               (dispatch_int),
        .dispatch_lsu               (dispatch_lsu),
        .dispatch_mul               (dispatch_mul),
        .lsu_busy                   (lsu_busy),
        .rename_out                 (rename_in),
        .rename_out_valid           (rename_valid),
        .stale_phys_reg             (stale_phys_reg),
        .rename_lookup_arch         (lookup_tag_in),
        .rename_lookup_phys         (lookup_tag_out),
        .ra_phys                    (rd_addr_a),
        .rb_phys                    (rd_addr_b),
        .exec_alu_op                (exec_alu_op),
        .exec_csr_op                (exec_csr_op),
        .int_exec_valid             (int_exec_valid),
        .lsu_exec_valid             (lsu_exec_valid),
        .mul_exec_valid             (mul_exec_valid),
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
        .kill_valid                 (kill_valid),
        .exec_resteer               (exec_resteer),
        .decode_exception           (decode_exception),
        .decode_except_id           (decode_except_id)
    );

    RXVIntExec #(
        .commit_order(commit_order)
    ) RXVIntExec (
        .clk                        (clk),
        .reset                      (reset),
        .kill_valid                 (kill_valid),
        .exec_valid                 (int_exec_valid),
        .exec_alu_op                (exec_alu_op),
        .exec_csr_op                (exec_csr_op),
        .exec_have_writeback        (exec_have_writeback),
        .exec_rd                    (exec_rd),
        .exec_id                    (exec_id),
        .op1                        (rs1_data),
        .op2                        (rs2_data),
        .exec_reg_addr              (int_exec_reg_wr_addr),
        .exec_reg_wr_en             (int_exec_reg_wr_en),
        .exec_reg_wr_data           (int_exec_reg_wr_data),
        .exec_complete              (int_exec_complete_valid),
        .exec_complete_id           (int_exec_complete_id),
        .exec_immed                 (exec_immed),
        .exec_opcode                (exec_opcode),
        .exec_branch_target         (exec_branch_target),
        .exec_uop                   (exec_uop),
        .exec_csr_rd_data           (exec_csr_rd_data),
        .exec_csr_wr_addr           (exec_csr_wr_addr),
        .exec_csr_wr_data           (exec_csr_wr_data),
        .exec_csr_wr_en             (exec_csr_wr_en),
        .exec_pc                    (exec_pc),
        .exec_next_pc               (exec_next_pc),
        .exec_prediction            (exec_prediction),
        .exec_predict_update        (exec_predict_update),
        .exec_predict_prev_strength (exec_predict_prev_strength),
        .exec_update_predict_taken  (exec_update_predict_taken),
        .exec_update_predict_address(exec_update_predict_address),
        .exec_update_predict_target (exec_update_predict_target),
        .exec_resteer               (int_exec_resteer),
        .exec_resteer_tgt           (int_exec_resteer_tgt),
        .mepc_in                    (mepc_val),
        .decode_exception           (decode_exception),
        .decode_except_id           (decode_except_id),
        .exec_exception             (exec_exception),
        .exec_except_id             (exec_except_id)
    );

    RXVMulExec #(
        .commit_order(commit_order)
    ) RXVMulExec (
        .clk                (clk),
        .reset              (reset),
        .kill_valid         (kill_valid),
        .exec_valid         (mul_exec_valid),
        .exec_have_writeback(exec_have_writeback),
        .exec_rd            (exec_rd),
        .exec_id            (exec_id),
        .op1                (rs1_data),
        .op2                (rs2_data),
        .exec_reg_addr      (mul_exec_reg_wr_addr),
        .exec_reg_wr_en     (mul_exec_reg_wr_en),
        .exec_reg_wr_data   (mul_exec_reg_wr_data),
        .exec_complete      (mul_exec_complete_valid),
        .exec_complete_id   (mul_exec_complete_id),
        .exec_uop           (exec_uop)
    );

    RXVLSU #(
        .commit_order(commit_order)
    ) RXVLSU (
        .clk                (clk),
        .reset              (reset),
        .icache_busy        (icache_busy),
        .icache_invalidate  (icache_invalidate),
        .kill_valid         (kill_valid),
        .exec_valid         (lsu_exec_valid),
        .exec_have_writeback(exec_have_writeback),
        .exec_rd            (exec_rd),
        .exec_id            (exec_id),
        .op1                (rs1_data),
        .op2                (rs2_data),
        .exec_immed         (exec_immed),
        .exec_pc            (exec_pc),
        .exec_next_pc       (exec_next_pc),
        .exec_uop           (exec_uop),
        .lsu_busy           (lsu_busy),
        .lsu_reg_busy       (lsu_reg_busy),
        .lsu_reg_addr       (lsu_reg_wr_addr),
        .lsu_reg_wr_en      (lsu_reg_wr_en),
        .lsu_reg_wr_data    (lsu_reg_wr_data),
        .lsu_complete       (lsu_complete_valid),
        .lsu_complete_id    (lsu_complete_id),
        .dcache_address     (dcache_address),
        .dcache_valid       (dcache_valid),
        .dcache_busy        (dcache_busy),
        .dcache_rdata       (dcache_dout),
        .dcache_wren        (dcache_wren),
        .dcache_bytesel     (dcache_bytesel),
        .dcache_wdata       (dcache_din),
        .dcache_invalidate  (dcache_invalidate),
        .dcache_clean       (dcache_clean),
        .lsu_exception      (lsu_exception),
        .lsu_except_id      (lsu_except_id),
        .lsu_busy_kill      (lsu_busy_kill),
        .lsu_resteer        (lsu_resteer),
        .lsu_resteer_tgt    (lsu_resteer_tgt),
        .global_stall_start (lsu_global_stall_start),
        .global_stall_end   (lsu_global_stall_end)
    );

    RXVRegisterFile #(
        .banked(banked_register_file)
    ) RXVRegisterFile (
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

    RXVCSRFile #(
        .vendorid    (vendorid),
        .archid      (archid),
        .impid       (impid),
        .commit_order(commit_order)
    ) RXVCSRFile (
        .clk           (clk),
        .reset         (reset),
        .valid_csr_out (decode_valid_csr),
        .rd_addr       (decode_csr_addr),
        .rd_data       (exec_csr_rd_data),
        .writeback_id  (int_complete_id),
        .wr_addr       (exec_csr_wr_addr),
        .wr_data       (exec_csr_wr_data),
        .wr_en         (exec_csr_wr_en),
        .mepc_out      (mepc_val),
        .mtvec_out     (mtvec_val),
        .mcause_out    (mcause_val),
        .exec_exception(exec_exception),
        .exec_except_id(exec_except_id),
        .lsu_exception (lsu_exception),
        .lsu_except_id (lsu_except_id),
        .cyclesh_wren  (pmu_cyclesh_wren),
        .cyclesl_wren  (pmu_cyclesl_wren),
        .instreth_wren (pmu_instreth_wren),
        .instretl_wren (pmu_instretl_wren),
        .pmu_cycles    (pmu_cycles),
        .pmu_instret   (pmu_instret)
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
        .rollback      (rename_rollback),
        .kill          (resteer_kill_valid),
        .lsu_busy_kill (lsu_busy_kill)
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
        .lsu_busy_kill_valid(lsu_busy_kill),
        .int_complete_id    (int_complete_id),
        .int_complete_valid (int_complete_valid),
        .lsu_complete_id    (lsu_complete_id),
        .lsu_complete_valid (lsu_complete_valid),
        .except_id          (except_id),
        .except_valid       (except_valid),
        .exception_pending  (exception_pending),
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

    RXVScheduler RXVScheduler (
        .clk                (clk),
        .reset              (reset),
        .dispatch_int       (dispatch_int),
        .dispatch_lsu       (dispatch_lsu),
        .dispatch_mul       (dispatch_mul),
        .global_stall_start (lsu_global_stall_start),
        .global_stall_end   (lsu_global_stall_end),
        .global_stall_active(global_stall_active),
        .int_ready          (int_ready),
        .lsu_ready          (lsu_ready),
        .mul_ready          (mul_ready)
    );

    RXVCommitter #(
        .commit_order(commit_order)
    ) RXVCommitter (
        .clk                   (clk),
        .reset                 (reset),
        .commit_empty          (commit_empty),
        .commit_in             (commit_out),
        .commit_complete       (commit_complete_out),
        .commit_killed         (commit_killed_out),
        .commit_excepted       (commit_excepted_out),
        .commit_valid          (commit_valid),
        .commit_id             (commit_id),
        .retired               (retired),
        .commit_rename_out     (commit_rename_out),
        .commit_rename_valid   (commit_rename_valid),
        .commit_rename_rollback(rename_rollback),
        .commit_reg_push       (reg_free),
        .commit_reg_reg        (reg_free_phys),
        .exception_resteer     (exception_resteer),
        .exception_resteer_tgt (exception_resteer_tgt),
        .mtvec_in              (mtvec_val),
        .mcause_in             (mcause_val)
    );

    RXVPMU RXVPMU (
        .clk          (clk),
        .reset        (reset),
        .retire_valid (retired),
        .cyclesh_wren (pmu_cyclesh_wren),
        .cyclesl_wren (pmu_cyclesl_wren),
        .instreth_wren(pmu_instreth_wren),
        .instretl_wren(pmu_instretl_wren),
        .csr_wrval    (exec_csr_wr_data),
        .pmu_cycles   (pmu_cycles),
        .pmu_instret  (pmu_instret)
    );

    always_comb begin
        rs1_data = exec_bypass_rs1 ? reg_wr_data : rd_data_a;
        rs2_data = exec_bypass_rs2 ? reg_wr_data : rd_data_b;
    end

    always_comb begin
        kill_valid = exec_resteer | exec_exception.valid | lsu_exception.valid | lsu_busy_kill;
    end

    always_comb begin
        resteer_kill_valid = exec_resteer | exec_exception.valid | lsu_exception.valid;
    end

    always_comb begin
        except_valid = lsu_exception.valid | (exec_exception.valid & ~exec_resteer);
        except_id    = exec_exception.valid ? exec_except_id : lsu_except_id;
    end

    always_comb begin
        reg_wr_en          = 'b0;
        reg_wr_addr        = 'b0;
        reg_wr_data        = 'b0;
        int_complete_id    = 'b0;
        int_complete_valid = 1'b0;

        if (lsu_complete_valid) begin
            reg_wr_en   = lsu_reg_wr_en;
            reg_wr_addr = lsu_reg_wr_addr;
            reg_wr_data = lsu_reg_wr_data;
        end

        if (int_exec_complete_valid) begin
            reg_wr_en          = int_exec_reg_wr_en;
            reg_wr_addr        = int_exec_reg_wr_addr;
            reg_wr_data        = int_exec_reg_wr_data;
            int_complete_valid = 1'b1;
            int_complete_id    = int_exec_complete_id;
        end

        if (mul_exec_complete_valid) begin
            reg_wr_en          = mul_exec_reg_wr_en;
            reg_wr_addr        = mul_exec_reg_wr_addr;
            reg_wr_data        = mul_exec_reg_wr_data;
            int_complete_valid = 1'b1;
            int_complete_id    = mul_exec_complete_id;
        end

        lsu_reg_busy = int_exec_reg_wr_en;
    end

    RXVAssert no_simultaneous_completion (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(int_exec_complete_valid && mul_exec_complete_valid))
    );

    always_comb begin
        dcache_device_memory = dcache_phys_out >= device_base && dcache_phys_out < device_end;
    end

    always_comb begin
        exec_resteer = int_exec_resteer | lsu_resteer;
        exec_resteer_tgt = ({30{int_exec_resteer}} & int_exec_resteer_tgt) |
                           ({30{lsu_resteer}} & lsu_resteer_tgt);
    end

`ifdef verilator
    `include "RXVTrace_cpp.svh"

    always_ff @(posedge clk) begin
        logic [commit_width-1:0] complete_id;

        if (int_exec_complete_valid) complete_id = int_exec_complete_id;
        else if (mul_exec_complete_valid) complete_id = mul_exec_complete_id;
        else complete_id = lsu_complete_id;

        if (reg_wr_en && |reg_wr_addr) begin
            // verilator lint_off UNUSED
            commit_entry ce = RXVCommitBuffer.commit_fifo.mem[complete_id];
            // verilator lint_on UNUSED
            trace_write_reg(32'(complete_id), ce.dest_reg.arch, reg_wr_data);
        end
    end
`endif  // verilator

endmodule
