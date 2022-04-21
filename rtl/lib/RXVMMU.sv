package RXVMMU;

    // verilator lint_off UNUSED
    localparam integer asid_bits = 5;
    // verilator lint_on UNUSED

    typedef struct packed {
        logic [11:0] ppn1;
        logic [9:0] ppn0;
        logic [1:0] rsw;
        logic dirty;
        logic accessed;
        logic page_global;
        logic user;
        logic exec;
        logic write;
        logic read;
        logic valid;
    } sv32_pte_t;

    typedef struct packed {
        logic [31:12] pa;
        logic dirty;
        logic accessed;
        logic page_global;
        logic user;
        logic exec;
        logic write;
        logic read;
        logic valid;
        // Translation ASID, ignored for global mappings
        logic [asid_bits-1:0] asid;
    } translation_t  /* verilator public */;

    typedef enum bit [2:0] {
        TLB_INV_NONE,
        TLB_INV_ALL,
        TLB_INV_ASID_ONLY,
        TLB_INV_ADDR_ONLY,
        TLB_INV_ASID_ADDR
    } tlb_inv_op  /* verilator public */;

`ifdef verilator
    // verilator lint_off UNUSED

    function logic [31:12] translation_pa;
        // verilator public
        input translation_t translation;
        translation_pa = translation.pa;
    endfunction

    function logic translation_dirty;
        // verilator public
        input translation_t translation;
        translation_dirty = translation.dirty;
    endfunction

    function logic translation_accessed;
        // verilator public
        input translation_t translation;
        translation_accessed = translation.accessed;
    endfunction

    function logic translation_page_global;
        // verilator public
        input translation_t translation;
        translation_page_global = translation.page_global;
    endfunction

    function logic translation_user;
        // verilator public
        input translation_t translation;
        translation_user = translation.user;
    endfunction

    function logic translation_exec;
        // verilator public
        input translation_t translation;
        translation_exec = translation.exec;
    endfunction

    function logic translation_write;
        // verilator public
        input translation_t translation;
        translation_write = translation.write;
    endfunction

    function logic translation_read;
        // verilator public
        input translation_t translation;
        translation_read = translation.read;
    endfunction

    function logic translation_valid;
        // verilator public
        input translation_t translation;
        translation_valid = translation.valid;
    endfunction

    function logic [asid_bits-1:0] translation_asid;
        // verilator public
        input translation_t translation;
        translation_asid = translation.asid;
    endfunction

    // verilator lint_on UNUSED
`endif  // verilator

endpackage
