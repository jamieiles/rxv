`default_nettype none
module RXVICache #(
    parameter nr_lines        = 4,
    parameter nr_ways         = 4,
    parameter line_size_bytes = 16
) (
    input  logic                       clk,
    input  logic                       reset,
    // To memory
           MemInterface.Manager        bus,
    // To CPU
    input  logic                [31:2] address,
    input  logic                       valid,
    output logic                       busy,
    output logic                [31:0] dout,
    input  logic                       invalidate
);

    localparam offset_bits = $clog2(line_size_bytes / 4);
    localparam index_bits = $clog2(nr_lines);
    localparam tag_bits = 30 - index_bits - offset_bits;
    localparam way_bits = $clog2(nr_ways);
    localparam fill_beats = 4'((line_size_bytes / 4) - 'b1);
    initial assert (offset_bits + index_bits + tag_bits == 30);

    // verilator lint_off UNUSED
    function [tag_bits-1:0] addr_tag;
        input [31:2] address_in;
        addr_tag = address_in[2+offset_bits+index_bits+:tag_bits];
    endfunction

    function [index_bits-1:0] addr_index;
        input [31:2] address_in;
        addr_index = address_in[2+offset_bits+:index_bits];
    endfunction

    function [offset_bits-1:0] addr_offset;
        input [31:2] address_in;
        addr_offset = address_in[2+:offset_bits];
    endfunction
    // verilator lint_on UNUSED

    logic [ index_bits-1:0] index;
    logic [offset_bits-1:0] data_offset;
    logic [    nr_ways-1:0] wren;
    logic [           31:0] way_dout              [0:nr_ways-1];
    logic [   tag_bits-1:0] way_tag               [0:nr_ways-1];
    logic [    nr_ways-1:0] way_valid;
    logic                   miss;
    logic [offset_bits-1:0] offset;
    logic                   tag_compare_valid;
    logic [           31:2] lookup_address;
    logic                   filling;
    logic                   fill_complete;
    logic [    nr_ways-1:0] way_hit;
    logic [   way_bits-1:0] hit_way;
    logic [   way_bits-1:0] lru;
    logic                   lru_update;
    logic [   way_bits-1:0] lru_way_sel;
    logic [ index_bits-1:0] tag_ram_index;
    logic [ index_bits-1:0] invalidate_index;
    logic [     tag_bits:0] tag_write_val;
    logic [    nr_ways-1:0] tag_write_en;
    logic                   invalidating;
    logic [    nr_ways-1:0] way_write_en;
    logic                   start_access;
    logic                   need_fill;
    logic                   invalidating_update;
    logic [ index_bits-1:0] invalidate_index_next;
    logic                   filling_next;
    logic [           31:2] bus_address;
    logic                   bus_valid;
    logic                   bus_complete;
    logic [           31:0] bus_rdata;
    logic [            3:0] bus_beat_num;
    logic [            3:0] bus_beat_num_next;
    logic                   bus_beat_ack;

    BusAdapter BusAdapter (
        .clk          (clk),
        .reset        (reset),
        .bus          (bus),
        .valid        (bus_valid),
        .complete     (bus_complete),
        .address      (bus_address),
        .wren         (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .wdata        (),
        .bytesel      (),
        // verilator lint_on PINCONNECTEMPTY
        .rdata        (bus_rdata),
        .len          (fill_beats),
        .beat_num     (bus_beat_num),
        .beat_num_next(bus_beat_num_next),
        .beat_ack     (bus_beat_ack)
    );

    generate
        genvar way;
        for (way = 0; way < nr_ways; way = way + 1) begin : way_data
            RAM #(
                .depth(nr_lines * line_size_bytes / 4),
                .width(32)
            ) DataRam (
                .clk (clk),
                .addr({index, data_offset}),
                .wren(way_write_en[way]),
                .din (bus_rdata),
                .dout(way_dout[way])
            );

            RAM #(
                .depth(nr_lines),
                .width(tag_bits + 1)
            ) TagRam (
                .clk (clk),
                .addr(tag_ram_index),
                .wren(tag_write_en[way]),
                .din (tag_write_val),
                .dout({way_valid[way], way_tag[way]})
            );
        end
    endgenerate

    OneHotDecode #(
        .width(nr_ways)
    ) HitDecoder (
        .d(way_hit),
        .q(hit_way)
    );

    BitPLRU #(
        .width(nr_ways),
        .depth(nr_lines)
    ) BitPLRU (
        .clk       (clk),
        .read_index(index),
        .access_way(lru_way_sel),
        .valid     (lru_update),
        .lru_out   (lru)
    );

    always_comb begin
        integer i;

        tag_write_val = {~invalidating, addr_tag(lookup_address)};
        tag_ram_index = invalidating ? invalidate_index :
            busy ? addr_index(lookup_address) : addr_index(address);

        for (i = 0; i < nr_ways; i = i + 1'b1) begin
            tag_write_en[i] = invalidating || (filling && bus_complete && way_bits'(i) == lru);
            way_write_en[i] = way_bits'(i) == lru && (bus_beat_ack);
            way_hit[i]      = way_valid[i] && way_tag[i] == addr_tag(lookup_address);
        end

        lru_update  = tag_compare_valid && !miss;
        lru_way_sel = hit_way;
        if (|tag_write_en) begin
            lru_update  = 1'b1;
            lru_way_sel = lru;
        end
    end

    always_comb begin
        index       = filling ? addr_index(lookup_address) : addr_index(address);
        miss        = tag_compare_valid && ~|way_hit;
        busy        = miss || filling || invalidating;
        dout        = !miss ? way_dout[hit_way] : 32'b0;
        data_offset = filling ? offset_bits'(bus_beat_num) : addr_offset(address);
    end

    always_comb begin
        filling_next = filling;

        start_access = valid && !miss && !filling && !(invalidate || invalidating);
        need_fill    = miss && !filling;

        if (need_fill || fill_complete) begin
            filling_next = need_fill;
        end

        invalidating_update   = invalidate || &invalidate_index;
        invalidate_index_next = invalidate_index + 1'b1;
        bus_address           = lookup_address;
        bus_valid             = need_fill;
    end

    RXVDFF invalidating_dff (
        .clk  (clk),
        .reset(reset),
        .en   (invalidating_update),
        .d    (invalidate),
        .q    (invalidating)
    );

    RXVDFF filling_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (filling_next),
        .q    (filling)
    );

    RXVDFF #(
        .width(index_bits)
    ) invalidate_index_dff (
        .clk  (clk),
        .reset(reset),
        .en   (invalidating),
        .d    (invalidate_index_next),
        .q    (invalidate_index)
    );

    RXVDFF fill_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bus_complete),
        .q    (fill_complete)
    );

    RXVDFF tag_compare_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (valid),
        .q    (tag_compare_valid)
    );

    RXVDFF #(
        .width(30)
    ) lookup_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (start_access),
        .d    (address),
        .q    (lookup_address)
    );

endmodule
