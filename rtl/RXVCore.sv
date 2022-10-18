`include "RXV.svh"

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
import RXVTypes::commit_width;
import RXVTrace::trace_write_reg;
import RXVTrace::trace_write_csr;
import RXVCSR::RXVException;
import RXVCSR::mtvec_t;
import RXVCSR::mcause_t;
import RXVCSR::mstatus_t;
import RXVCSR::privilege_t;
import RXVCSR::stperms_t;
import RXVMMU::translation_t;
import RXVMMU::tlb_inv_op;
import RXVMMU::asid_bits;
import RXVMMU::pmp_perms;

module RXVCore #(
    parameter int          icache_nr_lines        = 16,
    parameter int          icache_nr_ways         = 4,
    parameter int          icache_line_size_bytes = 32,
    parameter int          dcache_nr_lines        = 16,
    parameter int          dcache_nr_ways         = 4,
    parameter int          dcache_line_size_bytes = 32,
    parameter int          btb_num_entries        = 256,
    parameter int          btb_tag_bits           = 10,
    parameter int          banked_register_file   = 0,
    parameter int          num_itlb_entries       = 8,
    parameter int          num_dtlb_entries       = 8,
    parameter logic [31:0] reset_address          = 32'h80000000,
    parameter logic [31:0] vendorid               = 0,
    parameter logic [31:0] archid                 = 0,
    parameter logic [31:0] impid                  = 0,
    parameter logic [31:0] device_base            = 32'hf0000000,
    parameter logic [31:0] device_end             = 32'hffffffff
) (
    `POWER_PIN_PORTS
    input logic                       clk,
    input logic                       reset,
          MemInterface.Manager        instruction_bus,
          MemInterface.Manager        data_bus,
    input logic                [63:0] mtime,
    input logic                       mtime_irq,
    input logic                       ext_irq
);

    logic          [             31:2] icache_address;
    logic                              icache_valid;
    logic                              icache_busy;
    logic          [             31:0] icache_dout;
    logic                              icache_invalidate;
    logic          [             31:2] icache_phys;
    logic                              icache_phys_valid;

    logic          [             31:2] fetch_predict_address;
    rxv_prediction                     fetch_prediction;
    logic                              fetch_idle;
    translation_t                      fetch_translation;
    logic                              fetch_access_fault;
    logic                              fetch_tlb_busy;
    logic                              fetch_tlb_valid;
    logic          [             31:2] irq_epc;
    privilege_t                        current_privilege;

    logic                              schedule_int;
    logic                              schedule_lsu;
    logic                              schedule_mul;
    logic                              schedule_div;
    logic                              int_ready;
    logic                              lsu_ready;
    logic                              mul_ready;
    logic                              div_ready;

    logic                              decode_resteer;
    logic          [             31:2] decode_resteer_tgt;
    logic                              decode_fe_stall;
    logic                              decode_valid;
    logic                              decode_page_fault;
    logic                              decode_pmp_fault;
    logic          [             31:2] decode_pc;
    stperms_t                          decode_perms;
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
    logic          [             31:2] sepc_val;
    mstatus_t                          mstatus_val;
    RXVException                       exec_exception;
    logic          [ commit_width-1:0] exec_except_id;
    logic                              do_mret;
    logic                              do_sret;
    logic                              irq_pending;
    logic          [ commit_width-1:0] int_exec_complete_id;
    logic                              int_exec_complete_valid;
    logic                              int_exec_reg_wr_en;
    phys_reg_tag                       int_exec_reg_wr_addr;
    logic          [             31:0] int_exec_reg_wr_data;

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

    logic                              div_exec_valid;
    logic          [ commit_width-1:0] div_exec_complete_id;
    logic                              div_exec_complete_valid;
    logic                              div_exec_reg_wr_en;
    phys_reg_tag                       div_exec_reg_wr_addr;
    logic          [             31:0] div_exec_reg_wr_data;
    logic                              div_exec_busy;

    logic          [ commit_width-1:0] lsu_complete_id;
    logic                              lsu_complete_valid;
    logic                              lsu_reg_wr_en;
    phys_reg_tag                       lsu_reg_wr_addr;
    logic          [             31:0] lsu_reg_wr_data;
    logic                              lsu_reg_busy;
    logic                              lsu_busy_kill;
    logic                              lsu_global_stall_start;
    logic                              lsu_global_stall_end;
    logic          [             31:2] lsu_dcache_address;
    logic                              lsu_dcache_valid;
    logic                              lsu_dcache_busy;
    logic          [             31:0] lsu_dcache_din;
    logic                              lsu_dcache_wren;
    logic          [              3:0] lsu_dcache_bytesel;
    logic          [             31:0] lsu_dcache_dout;
    logic          [             31:2] lsu_dcache_phys_in;
    logic                              lsu_dcache_phys_valid;
    logic                              lsu_dcache_invalidate;
    logic                              lsu_dcache_clean;
    translation_t                      lsu_translation;
    logic                              lsu_access_fault;
    logic                              lsu_tlb_busy;
    tlb_inv_op                         lsu_tlb_inv_op;
    logic          [    asid_bits-1:0] lsu_tlb_inv_asid;
    logic          [            31:12] lsu_tlb_inv_addr;

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
    logic          [             31:2] dcache_phys_in;
    logic                              dcache_phys_valid;
    logic          [             31:2] dcache_phys_out;
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
    //verilator lint_off UNUSED
    logic          [ commit_width-1:0] commit_id;
    //verilator lint_on UNUSED
    logic                              retired;
    logic                              exception_cleanup;
    logic                              exception_priv_change;
    logic                              exception_busy_wait;
    logic                              exception_resteer;
    logic          [             31:2] exception_resteer_tgt;

    phys_reg_tag                       busy_reg_in;
    logic                              busy_valid_in;
    logic          [num_phys_regs-1:0] scoreboard_busy;

    logic                              pmu_cyclesh_wren;
    logic                              pmu_cyclesl_wren;
    logic                              pmu_cycles_inhibit;
    logic                              pmu_instreth_wren;
    logic                              pmu_instretl_wren;
    logic                              pmu_instret_inhibit;
    logic          [             63:0] pmu_cycles;
    logic          [             63:0] pmu_instret;

    logic                              irq_resteer;
    logic          [             31:2] irq_resteer_tgt;

    logic          [             31:2] mmu_dcache_address;
    logic                              mmu_dcache_valid;
    logic                              mmu_dcache_busy;
    logic          [             31:0] mmu_dcache_rdata;
    logic          [             31:2] mmu_dcache_phys_in;
    logic                              mmu_dcache_phys_valid;
    logic                              mmu_busy;
    logic                              mmu_dcache_grant;
    logic          [            31:12] translation_base;
    logic          [    asid_bits-1:0] active_asid;
    logic                              i_tlb_enabled;
    logic                              d_tlb_enabled;
    logic                              pmp_update_cfg;
    logic          [              1:0] pmp_update_addr_idx;
    logic                              pmp_update_addr;
    logic          [             31:0] pmp_cfg_read_data;
    logic          [              1:0] pmp_address_read_idx;
    logic          [             31:0] pmp_address_read_data;
    logic          [             31:2] pmp_data_addr;
    pmp_perms                          pmp_data_perms;
    logic          [             31:2] pmp_instr_addr;
    pmp_perms                          pmp_instr_perms;

`ifdef RXV_TRACE
    logic [31:12] decode_phys;
`endif  // RXV_TRACE

    RXVICache #(
        .nr_lines       (icache_nr_lines),
        .nr_ways        (icache_nr_ways),
        .line_size_bytes(icache_line_size_bytes)
    ) RXVICache (
`ifdef USE_POWER_PINS
        `POWER_PIN_CONNECT
`endif
        .clk       (clk),
        .reset     (reset),
        .bus       (instruction_bus),
        .address   (icache_address),
        .valid     (icache_valid),
        .busy      (icache_busy),
        .dout      (icache_dout),
        .invalidate(icache_invalidate),
        .phys_in   (icache_phys),
        .phys_valid(icache_phys_valid)
    );

    RXVBranchPredictor #(
        .num_entries(btb_num_entries),
        .tag_bits   (btb_tag_bits)
    ) RXVBranchPredictor (
`ifdef USE_POWER_PINS
        `POWER_PIN_CONNECT
`endif
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
        .current_privilege     (current_privilege),
        .mstatus               (mstatus_val),
        .except_valid          (except_valid),
        .exception_pending     (exception_pending),
        .global_stall_active   (global_stall_active),
        .irq_pending           (irq_pending),
        .fetch_idle            (fetch_idle),
        .irq_epc               (irq_epc),
        .icache_address        (icache_address),
        .icache_valid          (icache_valid),
        .icache_busy           (icache_busy),
        .icache_instr          (icache_dout),
        .icache_phys           (icache_phys),
        .icache_phys_valid     (icache_phys_valid),
        .fetch_tlb_valid       (fetch_tlb_valid),
        .fetch_translation     (fetch_translation),
        .fetch_access_fault    (fetch_access_fault),
        .fetch_tlb_busy        (fetch_tlb_busy),
        .branch_predict_address(fetch_predict_address),
        .prediction            (fetch_prediction),
        .decode_resteer        (decode_resteer),
        .decode_resteer_tgt    (decode_resteer_tgt),
        .decode_fe_stall       (decode_fe_stall),
        .decode_valid          (decode_valid),
        .decode_page_fault     (decode_page_fault),
        .decode_pmp_fault      (decode_pmp_fault),
        .decode_pc             (decode_pc),
        .decode_perms          (decode_perms),
`ifdef RXV_TRACE
        .decode_phys           (decode_phys),
`endif  // RXV_TRACE
        .decode_next_pc        (decode_next_pc),
        .decode_prediction     (decode_prediction),
        .decode_instr          (decode_instr),
        .exec_resteer          (exec_resteer),
        .exec_resteer_tgt      (exec_resteer_tgt),
        .exception_resteer     (exception_resteer),
        .exception_resteer_tgt (exception_resteer_tgt)
    );

    RXVDecode RXVDecode (
        .clk                        (clk),
        .reset                      (reset),
        .current_privilege          (current_privilege),
        .decode_valid               (decode_valid),
        .decode_page_fault          (decode_page_fault),
        .decode_pmp_fault           (decode_pmp_fault),
        .decode_pc                  (decode_pc),
        .decode_perms               (decode_perms),
`ifdef RXV_TRACE
        .decode_phys                (decode_phys),
`endif  // RXV_TRACE
        .decode_next_pc             (decode_next_pc),
        .decode_prediction          (decode_prediction),
        .decode_instr               (decode_instr),
        .decode_predict_kill        (decode_predict_kill),
        .decode_predict_kill_address(decode_kill_address),
        .decode_resteer             (decode_resteer),
        .decode_resteer_tgt         (decode_resteer_tgt),
        .decode_fe_stall            (decode_fe_stall),
        .decode_csr_addr            (decode_csr_addr),
        .mstatus_in                 (mstatus_val),
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
        .div_ready                  (div_ready),
        .schedule_int               (schedule_int),
        .schedule_lsu               (schedule_lsu),
        .schedule_mul               (schedule_mul),
        .schedule_div               (schedule_div),
        .lsu_busy                   (lsu_busy),
        .mmu_busy                   (mmu_busy),
        .div_exec_busy              (div_exec_busy),
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
        .div_exec_valid             (div_exec_valid),
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

    RXVIntExec RXVIntExec (
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
        .sepc_in                    (sepc_val),
        .do_mret                    (do_mret),
        .do_sret                    (do_sret),
        .decode_exception           (decode_exception),
        .decode_except_id           (decode_except_id),
        .exec_exception             (exec_exception),
        .exec_except_id             (exec_except_id),
        .current_privilege          (current_privilege)
    );

    RXVMulExec RXVMulExec (
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

    RXVDivExec RXVDivExec (
        .clk                (clk),
        .reset              (reset),
        .kill_valid         (kill_valid),
        .exec_valid         (div_exec_valid),
        .exec_have_writeback(exec_have_writeback),
        .exec_rd            (exec_rd),
        .exec_id            (exec_id),
        .op1                (rs1_data),
        .op2                (rs2_data),
        .exec_reg_addr      (div_exec_reg_wr_addr),
        .exec_reg_wr_en     (div_exec_reg_wr_en),
        .exec_reg_wr_data   (div_exec_reg_wr_data),
        .exec_complete      (div_exec_complete_valid),
        .exec_complete_id   (div_exec_complete_id),
        .exec_uop           (exec_uop),
        .busy               (div_exec_busy)
    );

    RXVLSU #(
        .line_size_bytes(dcache_line_size_bytes)
    ) RXVLSU (
        .clk                 (clk),
        .reset               (reset),
        .icache_busy         (icache_busy),
        .icache_invalidate   (icache_invalidate),
        .kill_valid          (kill_valid),
        .exec_valid          (lsu_exec_valid),
        .exec_have_writeback (exec_have_writeback),
        .exec_rd             (exec_rd),
        .exec_id             (exec_id),
        .op1                 (rs1_data),
        .op2                 (rs2_data),
        .exec_immed          (exec_immed),
        .exec_pc             (exec_pc),
        .exec_next_pc        (exec_next_pc),
        .exec_uop            (exec_uop),
        .lsu_busy            (lsu_busy),
        .lsu_reg_busy        (lsu_reg_busy),
        .lsu_reg_addr        (lsu_reg_wr_addr),
        .lsu_reg_wr_en       (lsu_reg_wr_en),
        .lsu_reg_wr_data     (lsu_reg_wr_data),
        .lsu_complete        (lsu_complete_valid),
        .lsu_complete_id     (lsu_complete_id),
        .dcache_address      (lsu_dcache_address),
        .dcache_valid        (lsu_dcache_valid),
        .dcache_busy         (lsu_dcache_busy),
        .dcache_rdata        (lsu_dcache_dout),
        .dcache_wren         (lsu_dcache_wren),
        .dcache_bytesel      (lsu_dcache_bytesel),
        .dcache_wdata        (lsu_dcache_din),
        .dcache_invalidate   (lsu_dcache_invalidate),
        .dcache_clean        (lsu_dcache_clean),
        .dcache_phys         (lsu_dcache_phys_in),
        .dcache_phys_valid   (lsu_dcache_phys_valid),
        .dcache_device_memory(dcache_device_memory),
        .lsu_translation     (lsu_translation),
        .lsu_access_fault    (lsu_access_fault),
        .lsu_tlb_busy        (lsu_tlb_busy),
        .lsu_tlb_inv_op      (lsu_tlb_inv_op),
        .lsu_tlb_inv_asid    (lsu_tlb_inv_asid),
        .lsu_tlb_inv_addr    (lsu_tlb_inv_addr),
        .lsu_tlb_enabled     (d_tlb_enabled),
        .current_privilege   (current_privilege),
        .mstatus             (mstatus_val),
        .lsu_exception       (lsu_exception),
        .lsu_except_id       (lsu_except_id),
        .lsu_busy_kill       (lsu_busy_kill),
        .lsu_resteer         (lsu_resteer),
        .lsu_resteer_tgt     (lsu_resteer_tgt),
        .global_stall_start  (lsu_global_stall_start),
        .global_stall_end    (lsu_global_stall_end)
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
        .vendorid(vendorid),
        .archid  (archid),
        .impid   (impid)
    ) RXVCSRFile (
        .clk                  (clk),
        .reset                (reset),
        .valid_csr_out        (decode_valid_csr),
        .rd_addr              (decode_csr_addr),
        .rd_data              (exec_csr_rd_data),
        .writeback_id         (int_exec_complete_id),
        .wr_addr              (exec_csr_wr_addr),
        .wr_data              (exec_csr_wr_data),
        .wr_en                (exec_csr_wr_en),
        .mepc_out             (mepc_val),
        .sepc_out             (sepc_val),
        .mstatus_out          (mstatus_val),
        .exception_resteer_tgt(exception_resteer_tgt),
        .exec_exception       (exec_exception),
        .exec_except_id       (exec_except_id),
        .exception_priv_change(exception_priv_change),
        .lsu_exception        (lsu_exception),
        .lsu_except_id        (lsu_except_id),
        .do_mret              (do_mret),
        .do_sret              (do_sret),
        .irq_pending          (irq_pending),
        .fetch_idle           (fetch_idle),
        .commit_empty         (commit_empty),
        .exception_pending    (exception_pending),
        .irq_epc              (irq_epc),
        .irq_resteer          (irq_resteer),
        .irq_resteer_tgt      (irq_resteer_tgt),
        .mtime                (mtime),
        .mtime_irq            (mtime_irq),
        .ext_irq              (ext_irq),
        .cyclesh_wren         (pmu_cyclesh_wren),
        .cyclesl_wren         (pmu_cyclesl_wren),
        .pmu_cycles_inhibit   (pmu_cycles_inhibit),
        .instreth_wren        (pmu_instreth_wren),
        .instretl_wren        (pmu_instretl_wren),
        .pmu_instret_inhibit  (pmu_instret_inhibit),
        .pmu_cycles           (pmu_cycles),
        .pmu_instret          (pmu_instret),
        .current_privilege    (current_privilege),
        .pmp_addr_idx         (pmp_address_read_idx),
        .pmp_addr             (pmp_address_read_data),
        .pmp_cfg              (pmp_cfg_read_data),
        .pmp_update_cfg       (pmp_update_cfg),
        .pmp_update_addr      (pmp_update_addr),
        .pmp_update_addr_idx  (pmp_update_addr_idx),
        .translation_base     (translation_base),
        .active_asid          (active_asid),
        .i_tlb_enabled        (i_tlb_enabled),
        .d_tlb_enabled        (d_tlb_enabled)
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
`ifdef USE_POWER_PINS
        `POWER_PIN_CONNECT
`endif
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
        .phys_in      (dcache_phys_in),
        .phys_valid   (dcache_phys_valid),
        .phys_out     (dcache_phys_out),
        .device_memory(dcache_device_memory),
        .dout         (dcache_dout),
        .invalidate   (dcache_invalidate)
    );

    RXVDCacheArb RXVDCacheArb (
        .clk                  (clk),
        .reset                (reset),
        .lsu_dcache_address   (lsu_dcache_address),
        .lsu_dcache_valid     (lsu_dcache_valid),
        .lsu_dcache_busy      (lsu_dcache_busy),
        .lsu_dcache_rdata     (lsu_dcache_dout),
        .lsu_dcache_wren      (lsu_dcache_wren),
        .lsu_dcache_bytesel   (lsu_dcache_bytesel),
        .lsu_dcache_wdata     (lsu_dcache_din),
        .lsu_dcache_phys_in   (lsu_dcache_phys_in),
        .lsu_dcache_phys_valid(lsu_dcache_phys_valid),
        .lsu_dcache_invalidate(lsu_dcache_invalidate),
        .lsu_dcache_clean     (lsu_dcache_clean),
        .mmu_dcache_address   (mmu_dcache_address),
        .mmu_dcache_valid     (mmu_dcache_valid),
        .mmu_dcache_busy      (mmu_dcache_busy),
        .mmu_dcache_rdata     (mmu_dcache_rdata),
        .mmu_dcache_phys_in   (mmu_dcache_phys_in),
        .mmu_dcache_phys_valid(mmu_dcache_phys_valid),
        .mmu_dcache_grant     (mmu_dcache_grant),
        .dcache_address       (dcache_address),
        .dcache_valid         (dcache_valid),
        .dcache_busy          (dcache_busy),
        .dcache_rdata         (dcache_dout),
        .dcache_wren          (dcache_wren),
        .dcache_bytesel       (dcache_bytesel),
        .dcache_wdata         (dcache_din),
        .dcache_phys_in       (dcache_phys_in),
        .dcache_phys_valid    (dcache_phys_valid),
        .dcache_invalidate    (dcache_invalidate),
        .dcache_clean         (dcache_clean)
    );

    RXVPMP RXVPMP (
        .clk              (clk),
        .reset            (reset),
        .update_cfg       (pmp_update_cfg),
        .update_addr_idx  (pmp_update_addr_idx),
        .update_data      (exec_csr_wr_data),
        .update_addr      (pmp_update_addr),
        .cfg_read_data    (pmp_cfg_read_data),
        .address_read_idx (pmp_address_read_idx),
        .address_read_data(pmp_address_read_data),
        .data_addr        (pmp_data_addr),
        .data_perms       (pmp_data_perms),
        .instr_addr       (pmp_instr_addr),
        .instr_perms      (pmp_instr_perms)
    );

    RXVMMUTop #(
        .num_d_entries(num_dtlb_entries),
        .num_i_entries(num_itlb_entries)
    ) RXVMMUTop (
        .clk              (clk),
        .reset            (reset),
        .translation_base (translation_base),
        .d_va             (lsu_dcache_address[31:12]),
        .d_valid          (lsu_dcache_valid),
        .d_enabled        (d_tlb_enabled),
        .d_busy           (lsu_tlb_busy),
        .d_translation    (lsu_translation),
        .d_access_fault   (lsu_access_fault),
        .active_asid      (active_asid),
        .tlb_op           (lsu_tlb_inv_op),
        .inv_asid         (lsu_tlb_inv_asid),
        .inv_addr         (lsu_tlb_inv_addr),
        .i_va             (icache_address[31:12]),
        .i_valid          (fetch_tlb_valid),
        .i_enabled        (i_tlb_enabled),
        .i_busy           (fetch_tlb_busy),
        .i_translation    (fetch_translation),
        .i_access_fault   (fetch_access_fault),
        .dcache_address   (mmu_dcache_address),
        .dcache_valid     (mmu_dcache_valid),
        .dcache_busy      (mmu_dcache_busy),
        .dcache_rdata     (mmu_dcache_rdata),
        .dcache_phys_in   (mmu_dcache_phys_in),
        .dcache_phys_valid(mmu_dcache_phys_valid),
        .dcache_grant     (mmu_dcache_grant),
        .lsu_busy         (lsu_busy),
        .d_pmp_addr       (pmp_data_addr),
        .d_pmp            (pmp_data_perms),
        .i_pmp_addr       (pmp_instr_addr),
        .i_pmp            (pmp_instr_perms)
    );

    RXVCommitBuffer RXVCommitBuffer (
        .clk                (clk),
        .reset              (reset),
        .full               (commit_full),
        .dispatch_in        (dispatch_in),
        .dispatch_valid     (dispatch_valid),
        .dispatch_id        (dispatch_id),
        .kill_valid         (kill_valid),
        .lsu_busy_kill_valid(lsu_busy_kill),
        .int_complete_id    (int_exec_complete_id),
        .int_complete_valid (int_exec_complete_valid),
        .lsu_complete_id    (lsu_complete_id),
        .lsu_complete_valid (lsu_complete_valid),
        .mul_complete_id    (mul_exec_complete_id),
        .mul_complete_valid (mul_exec_complete_valid),
        .div_complete_id    (div_exec_complete_id),
        .div_complete_valid (div_exec_complete_valid),
        .except_id          (except_id),
        .except_valid       (except_valid),
        .exception_pending  (exception_pending),
        .exception_resteer  (exception_resteer),
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
        .schedule_int       (schedule_int),
        .schedule_lsu       (schedule_lsu),
        .schedule_mul       (schedule_mul),
        .schedule_div       (schedule_div),
        .global_stall_start (lsu_global_stall_start),
        .global_stall_end   (lsu_global_stall_end),
        .global_stall_active(global_stall_active),
        .int_ready          (int_ready),
        .lsu_ready          (lsu_ready),
        .mul_ready          (mul_ready),
        .div_ready          (div_ready)
    );

    RXVCommitter RXVCommitter (
        .clk                   (clk),
        .reset                 (reset),
        .commit_empty          (commit_empty),
        .commit_in             (commit_out),
        .commit_complete       (commit_complete_out),
        .commit_killed         (commit_killed_out),
        .commit_excepted       (commit_excepted_out),
        .commit_valid          (commit_valid),
        .retired               (retired),
        .lsu_busy              (lsu_busy),
        .div_exec_busy         (div_exec_busy),
        .commit_rename_out     (commit_rename_out),
        .commit_rename_valid   (commit_rename_valid),
        .commit_rename_rollback(rename_rollback),
        .commit_reg_push       (reg_free),
        .commit_reg_reg        (reg_free_phys),
        .exception_pending     (exception_pending),
        .exception_resteer     (exception_resteer),
        .exception_cleanup     (exception_cleanup),
        .exception_priv_change (exception_priv_change),
        .exception_busy_wait   (exception_busy_wait)
    );

    RXVPMU RXVPMU (
        .clk            (clk),
        .reset          (reset),
        .retire_valid   (retired),
        .cyclesh_wren   (pmu_cyclesh_wren),
        .cyclesl_wren   (pmu_cyclesl_wren),
        .cycles_inhibit (pmu_cycles_inhibit),
        .instreth_wren  (pmu_instreth_wren),
        .instretl_wren  (pmu_instretl_wren),
        .instret_inhibit(pmu_instret_inhibit),
        .csr_wrval      (exec_csr_wr_data),
        .pmu_cycles     (pmu_cycles),
        .pmu_instret    (pmu_instret)
    );

    always_comb begin
        rs1_data = exec_bypass_rs1 ? int_exec_reg_wr_data : rd_data_a;
        rs2_data = exec_bypass_rs2 ? int_exec_reg_wr_data : rd_data_b;
    end

    always_comb begin
        kill_valid = exec_resteer | exec_exception.valid | lsu_exception.valid | lsu_busy_kill;
    end

    always_comb begin
        resteer_kill_valid = exec_resteer | exec_exception.valid | lsu_exception.valid;
    end

    always_comb begin
        except_valid = lsu_exception.valid | exec_exception.valid;
        except_id    = exec_exception.valid ? exec_except_id : lsu_except_id;
    end

    always_comb begin
        reg_wr_en   = 'b0;
        reg_wr_addr = 'b0;
        reg_wr_data = 'b0;

        if (lsu_complete_valid && lsu_reg_wr_en) begin
            reg_wr_en   = lsu_reg_wr_en;
            reg_wr_addr = lsu_reg_wr_addr;
            reg_wr_data = lsu_reg_wr_data;
        end

        if (int_exec_complete_valid && int_exec_reg_wr_en) begin
            reg_wr_en   = int_exec_reg_wr_en;
            reg_wr_addr = int_exec_reg_wr_addr;
            reg_wr_data = int_exec_reg_wr_data;
        end

        if (mul_exec_complete_valid && mul_exec_reg_wr_en) begin
            reg_wr_en   = mul_exec_reg_wr_en;
            reg_wr_addr = mul_exec_reg_wr_addr;
            reg_wr_data = mul_exec_reg_wr_data;
        end

        if (div_exec_complete_valid && div_exec_reg_wr_en) begin
            reg_wr_en   = div_exec_reg_wr_en;
            reg_wr_addr = div_exec_reg_wr_addr;
            reg_wr_data = div_exec_reg_wr_data;
        end

        lsu_reg_busy = int_exec_reg_wr_en | mul_exec_reg_wr_en | div_exec_reg_wr_en;
    end

    always_comb begin
        mmu_busy = lsu_tlb_busy | fetch_tlb_busy;
    end

    RXVAssert no_simultaneous_writeback (
        .clk      (clk),
        .en       (1'b1),
        .condition(2'(int_exec_reg_wr_en) + 2'(mul_exec_reg_wr_en) + 2'(div_exec_reg_wr_en) <= 1)
    );

    always_comb begin
        dcache_device_memory = {dcache_phys_out, 2'b0} >= device_base && {dcache_phys_out, 2'b0} < device_end;
    end

    always_comb begin
        exec_resteer = int_exec_resteer | lsu_resteer | irq_resteer;
        exec_resteer_tgt = ({30{int_exec_resteer}} & int_exec_resteer_tgt) |
                           ({30{lsu_resteer}} & lsu_resteer_tgt) |
                           ({30{irq_resteer}} & irq_resteer_tgt);
    end

    RXVAssert no_simultaneous_resteer (
        .clk(clk),
        .en(1'b1),
        .condition((3'(int_exec_resteer) + 3'(lsu_resteer)) + 3'(irq_resteer) + 3'(exception_resteer) <= 3'b1)
    );

`ifdef verilator
    `include "RXVTrace_cpp.svh"

    generate
        if (banked_register_file == 0) begin
            always_ff @(posedge clk) begin
                if (commit_rename_valid) begin
                    trace_write_reg(32'(commit_out.parent_id), commit_out.dest_reg.arch,
                                    RXVRegisterFile.DFF.RXVRegisterFileDFF.read_reg(
                                    commit_out.dest_reg.phys));
                end

                if (((commit_valid && !commit_killed_out) || (commit_valid && commit_excepted_out))) begin
                    if (commit_excepted_out && !exception_cleanup && !exception_busy_wait)
                        trace_exception(32'(commit_out.parent_id));
                    if (commit_out.last || (commit_excepted_out && !exception_cleanup && !exception_busy_wait))
                        trace_end_instruction(32'(commit_out.parent_id));
                end
            end
        end else begin
            always_ff @(posedge clk) begin
                if (commit_rename_valid) begin
                    trace_write_reg(32'(commit_out.parent_id), commit_out.dest_reg.arch,
                                    RXVRegisterFile.RAM.RXVRegisterFileBanked.read_reg(
                                    commit_out.dest_reg.phys));
                end

                if (((commit_valid && !commit_killed_out) || (commit_valid && commit_excepted_out))) begin
                    if (commit_excepted_out && !exception_cleanup && !exception_busy_wait)
                        trace_exception(32'(commit_out.parent_id));
                    if (commit_out.last || (commit_excepted_out && !exception_cleanup && !exception_busy_wait))
                        trace_end_instruction(32'(commit_out.parent_id));
                end
            end
        end
    endgenerate
`endif  // verilator

endmodule
