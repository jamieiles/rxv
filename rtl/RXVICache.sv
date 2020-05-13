`default_nettype none
module RXVICache #(
    parameter nr_lines = 2,
    parameter nr_ways = 2,
    parameter line_size_bytes = 8
) (
    input logic clk,
    //verilator lint_off UNUSED
    input logic reset,
    //verilator lint_on UNUSED
    // To CPU
    input logic [29:0] cpu_addr,
    output reg [31:0] cpu_din,
    input logic cpu_access,
    output wire cpu_ack,
    output wire cache_busy,
    // Data snoop port
    output logic bus_request,
    input logic bus_grant,
    input logic bus_snoop_req,
    input logic [29:0] bus_snoop_addr_i,
    // To memory
    output wire [29:0] mem_addr,
    input logic [31:0] mem_din,
    output wire mem_access,
    input logic mem_ack
);

localparam words_per_line = line_size_bytes / 4;
localparam offset_bits = $clog2(words_per_line);
localparam index_bits = $clog2(nr_lines);
localparam tag_bits = 30 - index_bits - offset_bits;
localparam way_bits = $clog2(nr_ways);

// verilator lint_off UNUSED
function [tag_bits-1:0] tag;
    input logic[29:0] addr;
    begin
        tag = addr[offset_bits+index_bits+tag_bits-1:offset_bits+index_bits];
    end
endfunction

function [index_bits-1:0] index;
    input logic[29:0] addr;
    begin
        index = addr[offset_bits+index_bits-1:offset_bits];
    end
endfunction

function [offset_bits-1:0] offset;
    input logic[29:0] addr;
    begin
        offset = addr[offset_bits-1:0];
    end
endfunction
// verilator lint_on UNUSED

generate
genvar gen_way;
for (gen_way = 0; gen_way < nr_ways; gen_way = gen_way + 1) begin : way_generation
    DPRAM #(
        .depth(nr_lines),
        .width(1 + tag_bits)
    ) valid_tag_ram (
        .clk(clk),
        // Frontend
        .addr_a(cpu_index),
        .wren_a(1'b0),
        .din_a('b0),
        .dout_a({fe_valid_o[gen_way], fe_tag_o[gen_way]}),
        // Backend
        .addr_b(be_tag_lookup_addr),
        .wren_b(be_tag_wren[gen_way]),
        .din_b(be_tag_wr_val[gen_way]),
        .dout_b({be_valid_o[gen_way], be_tag_o[gen_way]})
    );

    DPRAMBE #(
        .depth(nr_lines * words_per_line),
        .byte_width(4)
    ) data_ram (
        .clk(clk),
        // Frontend
        .addr_a({cpu_index, cpu_offset}),
        .wren_a(1'b0),
        .din_a('b0),
        .byte_en_a(4'b1111),
        .dout_a(data_val[gen_way]),
        // Backend
        .addr_b({cpu_index, write_offset}),
        .byte_en_b(4'b1111),
        .wren_b(mem_ack && way_wr_sel[gen_way]),
        .din_b(mem_din),
        // verilator lint_off PINCONNECTEMPTY
        .dout_b()
        // verilator lint_on PINCONNECTEMPTY
    );

    assign fe_way_hit[gen_way] = fe_valid_o[gen_way] && fe_tag_o[gen_way] == tag(latched_addr);
    assign be_tag_wr_val[gen_way] = snoop_way_hit[gen_way] ? 'b0 : {write_offset == words_per_line[offset_bits-1:0] - 1'b1, tag_i};
    assign be_tag_wren[gen_way] = (mem_ack && way_wr_sel[gen_way]) || snoop_way_hit[gen_way];
    assign snoop_way_hit[gen_way] = last_bus_snoop_req && be_valid_o[gen_way] && be_tag_o[gen_way] == tag(latched_snoop_addr);

    `ifdef FORMAL
    initial assume(fe_valid_o[gen_way] == 1'b0);
    initial assume(fe_tag_o[gen_way] == 'b0);
    initial assume(fe_tag_o[gen_way] == 'b0);
    `endif
end
endgenerate

wire [nr_ways-1:0] fe_way_hit;
reg [nr_ways-1:0] way_wr_sel;
reg last_bus_snoop_req;

wire [index_bits-1:0] be_tag_lookup_addr = bus_snoop_req ?
    index(bus_snoop_addr_i) : cpu_index;

reg [29:0] latched_addr;
wire [index_bits-1:0] cpu_index = index(cpu_addr);
wire [offset_bits-1:0] cpu_offset = offset(cpu_addr);
reg [offset_bits-1:0] write_offset;

reg [way_bits:0] data_way_sel;
wire [nr_ways-1:0] snoop_way_hit;
wire [tag_bits+1-1:0] be_tag_wr_val[0:nr_ways-1];
wire [nr_ways-1:0] be_tag_wren;
wire [31:0] data_val [nr_ways];

reg last_access;
reg lookup_done;
wire fe_hit = last_access && |fe_way_hit;
wire start_lookup = cpu_access && (cpu_ack || !last_access);

wire [nr_ways-1:0] fe_valid_o;
wire [tag_bits-1:0] fe_tag_o [nr_ways];
wire [nr_ways-1:0] be_valid_o;
wire [tag_bits-1:0] be_tag_o [nr_ways];
wire [tag_bits-1:0] tag_i = tag(cpu_addr);

reg fill_complete;
wire fill_stb = lookup_done & ~fe_hit;
reg filling;

reg [29:0] latched_snoop_addr;

assign cpu_ack = fe_hit;
assign mem_access = last_access && (!fe_hit || filling) && !mem_ack && !fill_complete && bus_grant;
assign mem_addr = {cpu_addr[29:offset_bits], write_offset};
assign cache_busy = filling | fill_complete;

// Frontend logic
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        last_access <= 1'b0;
        lookup_done <= 1'b0;
        latched_addr <= 'b0;
    end else begin
        latched_addr <= cpu_addr;
        last_access <= cpu_access;
        lookup_done <= start_lookup;
    end
end

always_comb begin
    cpu_din = data_val[0];

    for (data_way_sel = 'b0; data_way_sel < nr_ways[way_bits:0];
         data_way_sel = data_way_sel + 1'b1)
        if (fe_way_hit[data_way_sel[$clog2(nr_ways)-1:0]])
            cpu_din = data_val[data_way_sel[$clog2(nr_ways)-1:0]];
end

// Backend linefill logic
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        way_wr_sel <= 'b1;
        last_bus_snoop_req <= 1'b0;
        write_offset <= 'b0;
        bus_request <= 1'b0;
        fill_complete <= 1'b0;
        filling <= 1'b0;
        latched_snoop_addr <= 'b0;
    end else begin
        latched_snoop_addr <= bus_snoop_addr_i;
        last_bus_snoop_req <= bus_snoop_req;

        if (fill_stb) begin
            filling <= 1'b1;
            bus_request <= 1'b1;
        end

        if (mem_ack)
            write_offset <= write_offset + 1'b1;

        fill_complete <= 1'b0;
        if (mem_ack && write_offset == words_per_line[offset_bits-1:0] - 1'b1) begin
            filling <= 1'b0;
            fill_complete <= 1'b1;
            bus_request <= 1'b0;
            // Round robin line fill
            way_wr_sel <= {way_wr_sel[nr_ways-2:0], way_wr_sel[nr_ways-1]};
        end
    end
end

`ifdef FORMAL

`ifdef FORMAL_RXVICACHE
`define ASSUME assume
`else
`define ASSUME assert
`endif

localparam GRANT_TIMEOUT = (line_size_bytes / 4) * 2 + 4;
localparam TRANSACTION_TIMEOUT = GRANT_TIMEOUT * 2 + 4;

(* anyconst *)  wire [29:0] f_addr;
logic [31:0] f_data = 'b0;
reg f_valid = 1'b0;
wire f_index = index(f_addr);
reg f_past_valid = 1'b0;
reg [1:0] f_cpu_access_history = 2'b0;
reg [1:0] f_cpu_ack_history = 2'b0;
reg [7:0] transaction_timeout = TRANSACTION_TIMEOUT;
reg [7:0] grant_timeout = GRANT_TIMEOUT;
reg [$clog2(nr_ways):0] f_i;

wire f_snoop_hit = last_bus_snoop_req && |snoop_way_hit;

initial assume(reset == 1'b1);
initial assume(mem_ack == 1'b0);
initial assume(bus_grant == 1'b0);
initial assert(offset_bits+index_bits+tag_bits == 30);

always_ff @(posedge clk) begin
    f_cpu_access_history <= {f_cpu_access_history[0], cpu_access};
    f_cpu_ack_history <= {f_cpu_ack_history[0], cpu_ack};
end

always_ff @(posedge clk)
    f_past_valid <= 1'b1;

always_comb
    if (f_past_valid)
        assume(!reset);

always_ff @(posedge clk) begin
    if (f_past_valid && $past(mem_addr) == f_addr)
        `ASSUME(mem_din == f_data);

    if (f_past_valid && $past(cpu_access) && !cpu_ack) begin
        `ASSUME($stable(cpu_addr));
        `ASSUME($stable(cpu_access));
    end

    if (f_past_valid) begin
        `ASSUME(!(bus_grant && bus_snoop_req));
        `ASSUME(!(bus_grant && !$past(bus_request)));
    end

    if (f_past_valid && $past(bus_snoop_req))
        `ASSUME($stable(bus_snoop_addr_i));

    if (f_past_valid && $past(bus_grant) && bus_request)
        `ASSUME(bus_grant);
end

always_comb begin
    for (f_i = 'b0; f_i < nr_ways; f_i = f_i + 1'b1) begin
        // No fe_hit from multiple ways
        assert(!(|fe_way_hit[nr_ways-1:f_i] && |fe_way_hit[f_i-1:0]));
        // Snoop hit triggers invalidation
        if (snoop_way_hit[f_i]) begin
            assert(be_tag_wr_val[f_i] == 'b0);
            assert(be_tag_wren[f_i]);
        end
    end
end

always_ff @(posedge clk)
    if (cpu_ack && $past(cpu_addr) == f_addr)
        assert(cpu_din == f_data);

always_ff @(posedge clk)
    if (f_past_valid)
        assume(mem_ack == $past(mem_access));

always_ff @(posedge clk)
    if (mem_ack && cpu_index == f_index)
        f_valid <= cpu_addr == f_addr;

always_comb
    if (cpu_access)
        `ASSUME(eventually(cpu_ack));

always_ff @(posedge clk) begin
    if (cpu_access)
        transaction_timeout <= transaction_timeout - 1'b1;
    if ($rose(cpu_access) || (cpu_access && cpu_ack))
        transaction_timeout <= TRANSACTION_TIMEOUT;
    if (last_access)
        assert(|transaction_timeout);
end

always_ff @(posedge clk) begin
    if (bus_request)
        grant_timeout <= grant_timeout - 1'b1;
    if ($rose(bus_request) || (bus_request && bus_grant))
        grant_timeout <= GRANT_TIMEOUT;
    if (last_access)
        `ASSUME(grant_timeout != 'b0);
end

always_comb
    if (last_access && !fe_hit && !mem_ack && filling && bus_grant)
        assert(mem_access);

always_ff @(posedge clk)
    if ($rose(last_access) && !fe_hit)
        assert(fill_stb);

always_comb
    if (mem_access)
        assert(mem_addr[29:offset_bits] == cpu_addr[29:offset_bits]);

always_comb
    if (fe_hit)
        assert(!mem_access);

always_ff @(posedge clk)
    assert({cpu_addr[29:4],cpu_addr[3:2], cpu_addr[1:0]} == cpu_addr);

always_ff @(posedge clk)
    assert(!(fe_hit && filling));

always_comb
    assert(!(mem_access & !bus_grant));

always_comb
    assert(|way_wr_sel);

// Cached access without a line fill
always_comb cover(f_cpu_access_history == 2'b01 && cpu_ack);
// Back to back accesses
always_comb cover(f_cpu_ack_history == 2'b11 && cpu_ack);
// Single access
always_comb cover(cpu_ack);
// Multiple ways
always_comb cover(way_wr_sel[1]);
// Bus grant
always_comb cover(bus_grant);
// Snoop flush reuest
always_comb cover(bus_snoop_req);
// Snoop hit
always_comb cover(bus_snoop_req && f_snoop_hit);
// Snoop miss
always_ff @(posedge clk)
    cover(f_past_valid && $past(bus_snoop_req) && !f_snoop_hit);

`endif

endmodule
