package RXVTypes;

    localparam num_arch_regs = 32;
    localparam num_phys_regs = 48;
    localparam arch_reg_bits = $clog2(num_arch_regs);
    localparam phys_reg_bits = $clog2(num_phys_regs);

    typedef logic [arch_reg_bits-1:0] arch_reg_tag;
    typedef logic [phys_reg_bits-1:0] phys_reg_tag;

    typedef struct packed {
        arch_reg_tag arch;
        phys_reg_tag phys;
    } renamed_reg;

endpackage
