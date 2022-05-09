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

    typedef enum bit [2:0] {
        STATE_RUN = 3'b000,
        STATE_MISS = 3'b001,
        STATE_FLUSH = 3'b010,
        STATE_FILL = 3'b011,
        STATE_INVAL = 3'b100,
        STATE_CLEAN = 3'b101,
        STATE_UNCACHED = 3'b110,
        STATE_ACCESS_COMPLETE = 3'b111
    } state_t;

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

    logic   [    index_bits-1:0] index;
    logic   [   offset_bits-1:0] data_offset;
    logic   [      tag_bits-1:0] way_tag                [0:nr_ways-1];
    logic   [       nr_ways-1:0] way_valid;
    logic                        miss;
    logic                        tag_compare_valid;
    logic   [              31:2] lookup_address;
    logic   [       nr_ways-1:0] way_hit;
    logic   [      way_bits-1:0] hit_way;
    logic   [      way_bits-1:0] lru;
    logic                        lru_update;
    logic   [      way_bits-1:0] lru_way_sel;
    logic   [    index_bits-1:0] tag_ram_index;
    logic   [    index_bits-1:0] dirty_ram_index;
    logic   [    index_bits-1:0] cmo_index;
    logic   [    index_bits-1:0] cmo_index_next;
    logic   [        tag_bits:0] tag_write_val;
    logic   [       nr_ways-1:0] tag_write_en;
    logic                        start_access;
    logic                        data_write_en;
    logic   [      way_bits-1:0] data_way_sel;
    logic   [               3:0] data_write_bytesel;
    logic   [              31:0] data_din;
    logic   [       nr_ways-1:0] dirty_wren;
    logic                        dirty_next;
    logic   [       nr_ways-1:0] dirty;
    logic   [      way_bits-1:0] cmo_way;
    logic   [      way_bits-1:0] cmo_way_next;
    logic   [      way_bits-1:0] fill_way;
    logic   [      way_bits-1:0] fill_way_next;
    logic   [              31:0] dout_cached;
    logic   [              31:0] dout_uncached;
    logic   [               1:0] dout_use_uncached;
    logic   [               1:0] dout_use_uncached_next;
    logic   [               3:0] bus_len;
    logic   [              31:2] bus_address;
    logic                        bus_valid;
    logic                        bus_complete;
    logic   [              31:0] bus_rdata;
    // verilator lint_off UNUSED
    logic   [               3:0] bus_beat_num;
    logic   [               3:0] bus_beat_num_next;
    // verilator lint_on UNUSED
    logic   [               3:0] bus_bytesel;
    logic                        bus_beat_ack;
    logic                        bus_wren;
    logic   [data_addr_bits-1:0] data_ram_addr;
    logic   [              31:0] bus_wdata;
    logic                        cmo_active;
    logic                        lookup_device_memory;
    state_t                      state;
    state_t                      next_state;

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
                .addr(dirty_ram_index),
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
        .read_index(addr_index(lookup_address)),
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

        miss     = tag_compare_valid && ~|way_hit && ~(bus_complete && lookup_device_memory);
        phys_out = {address, 2'b0};

        unique case (state)
            STATE_RUN: busy = miss;
            STATE_UNCACHED: busy = ~bus_complete;
            default: busy = 1'b1;
        endcase
    end

    // Dirty RAM management
    always_comb begin
        integer i;
        for (i = 0; i < nr_ways; i = i + 1'b1) begin
            unique case (state)
                STATE_RUN: begin
                    dirty_wren[i] = tag_compare_valid && wren && way_hit[i];
                    dirty_next    = tag_compare_valid && wren;
                end
                STATE_CLEAN: begin
                    dirty_wren[i] = bus_complete && way_bits'(i) == cmo_way;
                    dirty_next    = 1'b0;
                end
                STATE_INVAL: begin
                    dirty_wren[i] = 1'b1;
                    dirty_next    = 1'b0;
                end
                STATE_FILL, STATE_FLUSH: begin
                    dirty_wren[i] = bus_complete && way_bits'(i) == fill_way;
                    dirty_next    = 1'b0;
                end
                default: begin
                    dirty_wren[i] = 1'b0;
                    dirty_next    = 1'b0;
                end
            endcase
            if (lookup_device_memory) dirty_wren[i] = 1'b0;
        end
    end

    always_comb begin
        cmo_active = state == STATE_INVAL || state == STATE_CLEAN || clean || invalidate;
    end

    // Tag RAM control
    always_comb begin
        integer i;

        tag_write_val = {state != STATE_INVAL, addr_tag(lookup_address)};
        tag_ram_index = cmo_active ? cmo_index :
            busy ? addr_index(lookup_address) : addr_index(address);
        for (i = 0; i < nr_ways; i = i + 1'b1) begin
            unique case (state)
                STATE_INVAL: tag_write_en[i] = 1'b1;
                STATE_FILL: tag_write_en[i] = bus_complete && way_bits'(i) == fill_way;
                default: tag_write_en[i] = 1'b0;
            endcase
        end
    end

    // Dirty RAM control
    always_comb begin
        dirty_ram_index = cmo_active ? cmo_index_next : addr_index(lookup_address);
    end

    // LRU update
    always_comb begin
        lru_update  = |tag_write_en | (tag_compare_valid & !miss);
        lru_way_sel = |tag_write_en ? fill_way : hit_way;
    end

    // Bus control
    always_comb begin
        unique case (state)
            STATE_FILL: begin
                bus_valid = 1'b1 & ~bus_complete;
                bus_wren = 1'b0;
                bus_len = fill_beats;
                bus_address = {
                    addr_tag(lookup_address), addr_index(lookup_address), offset_bits'('b0)
                };
                bus_wdata = din;  // Unused
                bus_bytesel = 4'b1111;
            end
            STATE_FLUSH: begin
                bus_valid   = 1'b1 & ~bus_complete;
                bus_wren    = 1'b1;
                bus_len     = fill_beats;
                bus_address = {way_tag[fill_way], addr_index(lookup_address), offset_bits'('b0)};
                bus_wdata   = dout_cached;
                bus_bytesel = 4'b1111;
            end
            STATE_CLEAN: begin
                bus_valid   = 1'b1 & ~bus_complete & dirty[cmo_way];
                bus_wren    = 1'b1;
                bus_len     = fill_beats;
                bus_address = {way_tag[cmo_way], cmo_index, offset_bits'('b0)};
                bus_wdata   = dout_cached;
                bus_bytesel = 4'b1111;
            end
            STATE_UNCACHED: begin
                bus_valid   = 1'b1 & ~bus_complete;
                bus_wren    = wren;
                bus_len     = 4'b0;
                bus_address = lookup_address;
                bus_wdata   = din;
                bus_bytesel = bytesel;
            end
            default: begin
                bus_valid   = 1'b0;
                bus_wren    = 1'b0;
                bus_len     = 4'b0;
                bus_address = 'b0;
                bus_wdata   = din;
                bus_bytesel = 'b0;
            end
        endcase
    end

    // Data RAM control
    always_comb begin
        unique case (state)
            STATE_FILL: begin
                data_write_en      = bus_beat_ack;
                data_write_bytesel = 4'b1111;
                data_way_sel       = fill_way;
                data_din           = bus_rdata;
                data_offset        = offset_bits'(bus_beat_num);
            end
            STATE_CLEAN: begin
                data_write_en = 1'b0;
                data_write_bytesel = bytesel;
                data_way_sel = cmo_way;
                data_din = bus_rdata;
                data_offset = bus_beat_ack ? offset_bits'(bus_beat_num_next) :
                    offset_bits'(bus_beat_num);
            end
            STATE_FLUSH: begin
                data_write_en = 1'b0;
                data_write_bytesel = bytesel;
                data_way_sel = fill_way;
                data_din = bus_rdata;
                data_offset = bus_beat_ack ? offset_bits'(bus_beat_num_next) :
                    offset_bits'(bus_beat_num);
            end
            STATE_RUN: begin
                data_write_en      = tag_compare_valid & ~miss & wren & ~lookup_device_memory;
                data_write_bytesel = bytesel;
                data_way_sel       = hit_way;
                data_din           = din;
                data_offset        = addr_offset(lookup_address);
            end
            default: begin
                data_write_en      = 1'b0;
                data_write_bytesel = bytesel;
                data_way_sel       = hit_way;
                data_din           = din;
                data_offset        = addr_offset(lookup_address);
            end
        endcase
    end

    // Cycle + fill/writeback control
    always_comb begin
        index        = state == STATE_CLEAN ? cmo_index : addr_index(lookup_address);
        start_access = valid & ~busy;
    end

    // Data output
    always_comb begin
        dout_use_uncached_next = {state == STATE_UNCACHED, dout_use_uncached[1]};
        dout                   = dout_use_uncached[0] ? dout_uncached : dout_cached;
    end

    // Cache maintenance operations
    always_comb begin
        unique case (state)
            STATE_INVAL: begin
                cmo_index_next = cmo_index + 1'b1;
                cmo_way_next   = cmo_way + 1'b1;
            end
            STATE_CLEAN: begin
                cmo_index_next = ~|dirty && &cmo_way ? cmo_index + 1'b1 : cmo_index;
                cmo_way_next   = !dirty[cmo_way] ? cmo_way + 1'b1 : cmo_way;
            end
            default: begin
                cmo_index_next = cmo_index;
                cmo_way_next   = cmo_way;
            end
        endcase
    end

    always_comb begin
        data_ram_addr = {data_way_sel, index, data_offset};
    end

    always_comb begin
        integer i;

        // First fill empty ways, then fall back to LRU
        fill_way_next = fill_way;
        if (state == STATE_MISS) begin
            fill_way_next = lru;
            if (~&way_valid) begin
                for (i = nr_ways - 1; i >= 0; i = i - 1) begin
                    if (!way_valid[i]) begin
                        fill_way_next = way_bits'(i);
                    end
                end
            end
        end
    end

    RXVAssert device_not_cached (
        .clk      (clk),
        .en       (state == STATE_RUN && tag_compare_valid && lookup_device_memory),
        .condition(miss)
    );

    always_comb begin
        unique case (state)
            STATE_RUN: begin
                next_state = STATE_RUN;
                if (invalidate) next_state = STATE_INVAL;
                if (clean) next_state = STATE_CLEAN;
                if (miss) next_state = STATE_MISS;
                if (tag_compare_valid && lookup_device_memory) next_state = STATE_UNCACHED;
            end
            STATE_MISS: begin
                next_state = dirty[fill_way_next] ? STATE_FLUSH : STATE_FILL;
            end
            STATE_FLUSH: begin
                next_state = bus_complete ? STATE_FILL : STATE_FLUSH;
            end
            STATE_FILL: begin
                next_state = bus_complete ? STATE_ACCESS_COMPLETE : STATE_FILL;
            end
            STATE_INVAL: begin
                next_state = &cmo_index ? STATE_RUN : STATE_INVAL;
            end
            STATE_CLEAN: begin
                next_state = (&cmo_index && &cmo_way) && ~|dirty ? STATE_RUN : STATE_CLEAN;
            end
            STATE_ACCESS_COMPLETE: begin
                next_state = STATE_RUN;
            end
            STATE_UNCACHED: begin
                next_state = bus_complete ? STATE_RUN : STATE_UNCACHED;
            end
            default: next_state = state;
        endcase
    end

    RXVDFF #(
        .width(way_bits)
    ) cmo_way_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (cmo_way_next),
        .q    (cmo_way)
    );

    RXVDFF #(
        .width(way_bits)
    ) fill_way_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (fill_way_next),
        .q    (fill_way)
    );

    RXVDFF #(
        .width(index_bits)
    ) cmo_index_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (cmo_index_next),
        .q    (cmo_index)
    );

    RXVDFF tag_compare_valid_dff (
        .clk  (clk),
        .reset(reset),
        .en   (~busy),
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

    RXVDFF #(
        .width(2)
    ) dout_use_uncached_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (dout_use_uncached_next),
        .q    (dout_use_uncached)
    );

    RXVDFF #(
        .width(32)
    ) dout_uncached_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (bus.rdata),
        .q    (dout_uncached)
    );

    RXVDFF #(
        .width($bits(state_t))
    ) state_dff (
        .clk  (clk),
        .reset(reset),
        .en   (1'b1),
        .d    (next_state),
        .q    (state)
    );

    RXVDFF lookup_device_memory_dff (
        .clk  (clk),
        .reset(reset),
        .en   (start_access),
        .d    (device_memory),
        .q    (lookup_device_memory)
    );

endmodule
