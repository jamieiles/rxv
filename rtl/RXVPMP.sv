`include "RXV.svh"

import RXVMMU::pmp_perms;

module RXVPMP (
    input  logic                     clk,
    input  logic                     reset,
    // CSR interface
    input  logic                     update_cfg,
    input  logic     [addr_bits-1:0] update_addr_idx,
    // verilator lint_off UNUSED
    input  logic     [         31:0] update_data,
    // verilator lint_on UNUSED
    input  logic                     update_addr,
    output logic     [         31:0] cfg_read_data,
    input  logic     [addr_bits-1:0] address_read_idx,
    output logic     [         31:0] address_read_data,
    // Data port
    input  logic     [         31:2] data_addr,
    output pmp_perms                 data_perms,
    // Instruction port
    input  logic     [         31:2] instr_addr,
    output pmp_perms                 instr_perms
);

    localparam num_entries = 4;
    localparam addr_bits = $clog2(num_entries);

    typedef struct packed {
        logic [31:12] addr;
        logic enabled;
        pmp_perms perms;
    } pmp_entry_t;

    pmp_entry_t       pmps          [num_entries];
    // verilator lint_off UNUSED
    logic       [7:0] pmp_cfg_update[          4];
    // verilator lint_on UNUSED

    function logic [31:2] pmp_mask;
        // verilator lint_off UNUSED
        input pmp_entry_t pmp;
        // verilator lint_on UNUSED

        pmp_mask = 30'hfff;
        for (int i = 12; i < 32; ++i) begin
            pmp_mask[i] = 1;
            if (!pmp.addr[i]) break;
        end

        pmp_mask = ~pmp_mask;
    endfunction

    function logic [31:2] pmp_base;
        input pmp_entry_t pmp;

        pmp_base = {pmp.addr, 10'b0} & pmp_mask(pmp);
    endfunction

    always_comb begin
        for (int i = 0; i < 4; ++i) pmp_cfg_update[i] = update_data[8*i+:8];
    end

    genvar pmp_i;
    generate
        for (pmp_i = 0; pmp_i < num_entries; ++pmp_i) begin : pmp_gen
            pmp_entry_t pmp_n;
            pmp_entry_t pmp_n_next;

            always_comb begin
                pmp_n_next = pmp_n;

                if (update_addr && addr_bits'(update_addr_idx) == pmp_i) begin
                    pmp_n_next.addr = update_data[29:10];
                end

                if (update_cfg) begin
                    pmp_n_next.enabled     = pmp_cfg_update[pmp_i][4:3] == 2'b11;
                    pmp_n_next.perms.read  = pmp_cfg_update[pmp_i][0];
                    pmp_n_next.perms.write = pmp_cfg_update[pmp_i][1];
                    pmp_n_next.perms.exec  = pmp_cfg_update[pmp_i][2];
                end
            end

            assign pmps[pmp_i] = pmp_n;

            RXVDFF #(
                .width($bits(pmp_entry_t))
            ) pmp_dff (
                .clk  (clk),
                .reset(reset),
                .en   (1'b1),
                .d    (pmp_n_next),
                .q    (pmp_n)
            );
        end
    endgenerate

    RXVAssert assert_no_simultaneous_pmp_update (
        .clk      (clk),
        .en       (1'b1),
        .condition(!(update_cfg && update_addr))
    );

    always_comb begin
        {instr_perms.read, instr_perms.write, instr_perms.exec} = 3'b111;

        for (int i = 0; i < num_entries; ++i) begin
            if (pmps[i].enabled && ((instr_addr & pmp_mask(pmps[i])) == pmp_base(pmps[i]))) begin
                instr_perms = pmps[i].perms;
                break;
            end
        end
    end

    always_comb begin
        {data_perms.read, data_perms.write, data_perms.exec} = 3'b111;

        for (int i = 0; i < num_entries; ++i) begin
            if (pmps[i].enabled && ((data_addr & pmp_mask(pmps[i])) == pmp_base(pmps[i]))) begin
                data_perms = pmps[i].perms;
                break;
            end
        end
    end

    always_comb begin
        cfg_read_data = 32'b0;

        for (int i = 0; i < 4; ++i) begin
            cfg_read_data[i*8+:8] = {
                3'b0,
                pmps[i].enabled ? 2'b11 : 2'b00,
                pmps[i].perms.exec,
                pmps[i].perms.write,
                pmps[i].perms.read
            };
        end
    end

    always_comb begin
        // verilator lint_off UNUSED
        pmp_entry_t pmp;
        // verilator lint_on UNUSED
        pmp               = pmps[address_read_idx];
        address_read_data = {2'b0, pmp.addr, 10'h3ff};
    end

endmodule
