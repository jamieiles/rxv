package RXVTypes;

    localparam num_arch_regs  /* verilator public */ = 32;
    localparam num_phys_regs  /* verilator public */ = 48;
    localparam arch_reg_bits  /* verilator public */ = $clog2(num_arch_regs);
    localparam phys_reg_bits  /* verilator public */ = $clog2(num_phys_regs);

    typedef logic [arch_reg_bits-1:0] arch_reg_tag;
    typedef logic [phys_reg_bits-1:0] phys_reg_tag;

    typedef struct packed {
        arch_reg_tag arch;
        phys_reg_tag phys;
    } renamed_reg;

    typedef struct packed {
        phys_reg_tag stale_phys;
        renamed_reg dest_reg;
        logic [31:2] pc;
        logic have_writeback;
    } commit_entry;

`ifdef verilator
    function commit_entry make_commit_entry;
        // verilator public
        input phys_reg_tag stale_phys_reg;
        input arch_reg_tag renamed_arch;
        input phys_reg_tag renamed_phys;
        input logic [31:2] pc;
        input logic have_writeback;

        begin
            make_commit_entry                = 'b0;
            make_commit_entry.stale_phys     = stale_phys_reg;
            make_commit_entry.dest_reg.arch  = renamed_arch;
            make_commit_entry.dest_reg.phys  = renamed_phys;
            make_commit_entry.pc             = pc;
            make_commit_entry.have_writeback = have_writeback;
        end
    endfunction

    // verilator lint_off UNUSED

    function phys_reg_tag commit_entry_stale;
        // verilator public
        input commit_entry ce;

        commit_entry_stale = ce.stale_phys;
    endfunction

    function arch_reg_tag commit_entry_dest_arch;
        // verilator public
        input commit_entry ce;

        commit_entry_dest_arch = ce.dest_reg.arch;
    endfunction

    function phys_reg_tag commit_entry_dest_phys;
        // verilator public
        input commit_entry ce;

        commit_entry_dest_phys = ce.dest_reg.phys;
    endfunction

    function logic [31:2] commit_entry_pc;
        // verilator public
        input commit_entry ce;

        commit_entry_pc = ce.pc;
    endfunction

    function logic commit_entry_have_writeback;
        // verilator public
        input commit_entry ce;

        commit_entry_have_writeback = ce.have_writeback;
    endfunction

    // verilator lint_on UNUSED
`endif

endpackage
