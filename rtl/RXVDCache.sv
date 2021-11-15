`default_nettype none
// Data cache
//
// Accesses take 3 cycles:
//   1. setup address to fetch tag/dirty status
//   2. compare tags, check PMA for device memory
//      issue read/write to data ram
//   3. read data available at dout
//
// Uncached accesses or a miss may take longer in which case the data will be
// valid one cycle after busy goes low to match hits
module RXVDCache #(
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
    input  logic                [31:0] din,
    input  logic                       wren,
    input  logic                [ 3:0] bytesel,
    output logic                [31:0] dout,
    input  logic                       invalidate,
    input  logic                       clean,
    output logic                [31:0] phys_out,
    input  logic                       device_memory
);

    localparam offset_bits = $clog2(line_size_bytes / 4);
    localparam index_bits = $clog2(nr_lines);
    localparam tag_bits = 30 - index_bits - offset_bits;
    localparam way_bits = $clog2(nr_ways);
    localparam fill_beats = 4'((line_size_bytes / 4) - 'b1);
    localparam data_ram_depth = nr_lines * line_size_bytes;
    localparam data_addr_bits = $clog2(data_ram_depth);
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

    logic [    index_bits-1:0] index;
    logic [   offset_bits-1:0] data_offset;
    logic [      tag_bits-1:0] way_tag                [0:nr_ways-1];
    logic [       nr_ways-1:0] way_valid;
    logic                      miss;
    logic                      tag_compare_valid;
    logic [              31:2] lookup_address;
    logic [       nr_ways-1:0] way_hit;
    logic [      way_bits-1:0] hit_way;
    logic [      way_bits-1:0] lru;
    logic                      lru_update;
    logic [      way_bits-1:0] lru_way_sel;
    logic [    index_bits-1:0] tag_ram_index;
    logic [    index_bits-1:0] cmo_index;
    logic [    index_bits-1:0] cmo_index_next;
    logic [        tag_bits:0] tag_write_val;
    logic [       nr_ways-1:0] tag_write_en;
    logic                      invalidating;
    logic                      invalidating_update;
    logic                      cleaning;
    logic                      cleaning_update;
    logic                      arvalid_next;
    logic                      awvalid_next;
    logic                      wvalid_next;
    logic                      wlast_next;
    logic                      start_access;
    logic                      need_fill;
    logic                      need_writeback;
    logic                      filling;
    logic                      filling_next;
    logic                      fill_complete;
    logic                      writing_back;
    logic                      writing_back_next;
    logic                      uncached_access;
    logic                      uncached_access_next;
    logic                      writeback_complete;
    logic                      data_write_en;
    logic [      way_bits-1:0] data_way_sel;
    logic [               3:0] write_bytesel;
    logic [              31:0] write_din;
    logic                      write_wren;
    logic                      write_wren_update;
    logic [               3:0] data_write_bytesel;
    logic [              31:0] data_din;
    logic [       nr_ways-1:0] dirty_wren;
    logic                      dirty_next;
    logic [       nr_ways-1:0] dirty;
    logic [      way_bits-1:0] cmo_way;
    logic [      way_bits-1:0] cmo_way_next;
    logic [              31:0] dout_cached;
    logic [              31:0] dout_uncached;
    logic [               1:0] dout_use_uncached;
    logic [               1:0] dout_use_uncached_next;
    logic [               3:0] bus_len;
    logic                      bus_active;
    logic                      bus_active_next;
    logic [              31:2] bus_address;
    logic                      bus_valid;
    logic                      bus_complete;
    logic [              31:0] bus_rdata;
    logic [               3:0] bus_beat_num;
    logic [               3:0] bus_beat_num_next;
    logic [               3:0] bus_bytesel;
    logic                      bus_beat_ack;
    logic                      bus_wren;
    logic [data_addr_bits-1:0] data_ram_addr;
    logic [              31:0] bus_wdata;

    BusAdapter BusAdapter (
        .clk          (clk),
        .reset        (reset),
        .bus          (bus),
        .valid        (bus_valid),
        .complete     (bus_complete),
        .address      (bus_address),
        .wren         (bus_wren),
        .wdata        (bus_wdata),
        .bytesel      (bus_bytesel),
        .rdata        (bus_rdata),
        .len          (bus_len),
        .beat_num     (bus_beat_num),
        .beat_num_next(bus_beat_num_next),
        .beat_ack     (bus_beat_ack)
    );

    RAMBE #(
        .depth     (nr_lines * line_size_bytes),
        .byte_width(4)
    ) DataRam (
        .clk    (clk),
        .addr   (data_ram_addr),
        .wren   (data_write_en),
        .din    (data_din),
        .byte_en(data_write_bytesel),
        .dout   (dout_cached)
    );

    generate
        genvar way;
        for (way = 0; way < nr_ways; way = way + 1) begin : way_data
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

            RAM #(
                .depth(nr_lines),
                .width(1)
            ) DirtyRam (
                .clk (clk),
                .addr(index),
                .wren(dirty_wren[way]),
                .din (dirty_next),
                .dout(dirty[way])
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

    // Hit detection
    always_comb begin
        integer i;
        for (i = 0; i < nr_ways; i = i + 1'b1) begin
            way_hit[i] = way_valid[i] && way_tag[i] == addr_tag(lookup_address);
        end

        miss = tag_compare_valid && ~|way_hit && ~((bus_complete) && device_memory);
        phys_out = {addr_tag(lookup_address), addr_index(lookup_address), offset_bits'(0), 2'b0};
        busy     = miss | filling | writing_back | invalidating | cleaning |
            (uncached_access_next & ~bus_complete);
    end

    // Dirty RAM management
    always_comb begin
        integer i;
        for (i = 0; i < nr_ways; i = i + 1'b1) begin
            dirty_wren[i] = !device_memory &&
                (invalidating ||
                 (writing_back && bus_complete && way_bits'(i) == lru) ||
                 (cleaning && bus_complete && way_bits'(i) == cmo_way) ||
                 (filling && bus_complete && way_bits'(i) == lru) ||
                 (write_wren && way_hit[i]));
        end
        dirty_next = invalidating || bus_complete || cleaning ? 1'b0 : !busy && !miss && write_wren;
    end

    // Uncached access control
    always_comb begin
        if (bus_complete) uncached_access_next = 1'b0;
        else if (tag_compare_valid && device_memory) uncached_access_next = 1'b1;
        else uncached_access_next = uncached_access;
    end

    // Tag RAM control
    always_comb begin
        integer i;
        tag_write_val = {~invalidating, addr_tag(lookup_address)};
        tag_ram_index = invalidating ? cmo_index :
            busy ? addr_index(lookup_address) : addr_index(address);
        for (i = 0; i < nr_ways; i = i + 1'b1) begin
            tag_write_en[i] = invalidating ||
                (filling && bus_complete && way_bits'(i) == lru) && ~device_memory;
        end
    end

    // LRU update
    always_comb begin
        lru_update  = |tag_write_en | (tag_compare_valid & !miss);
        lru_way_sel = |tag_write_en ? lru : hit_way;
    end

    // Bus control
    always_comb begin
        bus_valid = ((need_fill & ~(need_writeback | writing_back)) |
             (uncached_access & ~bus_active & ~write_wren)) |
             need_writeback |
             (miss & uncached_access & ~bus_active & write_wren);
        bus_wren = need_writeback | (miss & uncached_access & write_wren);
        bus_active_next = filling | writing_back | uncached_access;
        bus_len = uncached_access ? 4'b0 : fill_beats;
        bus_address = uncached_access ? lookup_address :
            bus_wren ? {way_tag[lru], addr_index(lookup_address), offset_bits'('b0)} :
            {addr_tag(lookup_address), addr_index(lookup_address), offset_bits'('b0)};
        bus_wdata = uncached_access ? write_din : dout_cached;
        bus_bytesel = uncached_access ? write_bytesel : 4'b1111;
    end

    // Data RAM control
    always_comb begin
        data_write_en = filling ? bus_beat_ack : ~miss & write_wren & ~device_memory;
        data_write_bytesel = filling ? 4'b1111 : write_bytesel;
        data_way_sel = cleaning ? cmo_way : filling || writing_back ? lru : hit_way;
        data_din = busy ? bus_rdata : din;
        data_offset = (writing_back && !bus_beat_ack) || filling ? offset_bits'(bus_beat_num) :
            writing_back && bus_beat_ack ? offset_bits'(bus_beat_num_next) :
            addr_offset(lookup_address);
    end

    // Cycle + fill/writeback control
    always_comb begin
        index = addr_index(lookup_address);
        start_access = valid & ~busy;
        write_wren_update = start_access | ~busy;

        need_writeback = ~device_memory & ((&dirty & miss & ~filling) |
            (cleaning & dirty[cmo_way])) & ~writing_back;
        writing_back_next = need_writeback || writeback_complete ? need_writeback : writing_back;

        need_fill = !device_memory && miss && !filling;
        filling_next = filling;
        if ((need_fill && !(need_writeback || writing_back)) || fill_complete)
            filling_next = need_fill;
    end

    // Data output
    always_comb begin
        dout_use_uncached_next = {uncached_access, dout_use_uncached[1]};
        dout                   = dout_use_uncached[0] ? dout_uncached : dout_cached;
    end

    // Cache maintenance operations
    always_comb begin
        invalidating_update = invalidate || &cmo_index;
        cleaning_update = clean || (&cmo_index && &cmo_way);
        cmo_index_next = invalidating || (cleaning && ~|dirty && &cmo_way) ? cmo_index + 1'b1 : cmo_index;
        cmo_way_next = cleaning && !dirty[cmo_way] ? cmo_way + 1'b1 : cmo_way;
    end

    always_comb begin
        data_ram_addr = {data_way_sel, index, data_offset};
    end

    DFF invalidating_dff (
        .clk  (clk),
        .reset(reset),
        .en   (invalidating_update),
        .d    (invalidate),
        .q    (invalidating)
    );

    DFF cleaning_dff (
        .clk  (clk),
        .reset(reset),
        .en   (cleaning_update),
        .d    (clean),
        .q    (cleaning)
    );

    DFF #(
        .width(way_bits)
    ) cmo_way_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (cmo_way_next),
        .q    (cmo_way)
    );

    DFF filling_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (filling_next),
        .q    (filling)
    );

    DFF writing_back_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (writing_back_next),
        .q    (writing_back)
    );

    DFF uncached_access_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (uncached_access_next),
        .q    (uncached_access)
    );

    DFF #(
        .width(index_bits)
    ) cmo_index_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (cmo_index_next),
        .q    (cmo_index)
    );

    DFF fill_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (~writing_back & bus_complete),
        .q    (fill_complete)
    );

    DFF writeback_complete_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bus_complete),
        .q    (writeback_complete)
    );

    DFF tag_compare_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (~busy),
        .d    (valid),
        .q    (tag_compare_valid)
    );

    DFF #(
        .width(30)
    ) lookup_address_dff (
        .clk  (clk),
        .reset(reset),
        .en   (start_access),
        .d    (address),
        .q    (lookup_address)
    );

    DFF #(
        .width(4)
    ) write_bytesel_dff (
        .clk  (clk),
        .reset(reset),
        .en   (start_access),
        .d    (bytesel),
        .q    (write_bytesel)
    );

    DFF #(
        .width(32)
    ) write_din_dff (
        .clk  (clk),
        .reset(reset),
        .en   (start_access),
        .d    (din),
        .q    (write_din)
    );

    DFF write_wren_dff (
        .clk  (clk),
        .reset(reset),
        .en   (write_wren_update),
        .d    (wren),
        .q    (write_wren)
    );

    DFF bus_active_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bus_active_next),
        .q    (bus_active)
    );

    DFF #(
        .width(2)
    ) dout_use_uncached_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dout_use_uncached_next),
        .q    (dout_use_uncached)
    );

    DFF #(
        .width(32)
    ) dout_uncached_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bus.rdata),
        .q    (dout_uncached)
    );

endmodule
