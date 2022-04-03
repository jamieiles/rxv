package RXVMMU;

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

    typedef union packed {
        logic [31:0] raw;
        sv32_pte_t   pte;
    } sv32_pte_union_t;

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
    } translation_t;

endpackage
