module BusTransactor #(
    integer latency = 4,
    integer words = 512
)(
    input logic clk,
    MemInterface.Subordinate bus
);

typedef enum bit[1:0] {
    READ_STATE_ADDRESS,
    READ_STATE_LATENCY_WAIT,
    READ_STATE_DATA
} read_state_t;

typedef enum bit[1:0] {
    WRITE_STATE_ADDRESS,
    WRITE_STATE_LATENCY_WAIT,
    WRITE_STATE_DATA,
    WRITE_STATE_ACK
} write_state_t;

localparam wait_bits = $clog2(latency);
localparam addr_bits = $clog2(words);

write_state_t write_state, next_write_state;
read_state_t read_state, next_read_state;

logic [wait_bits-1:0] read_wait_counter;
logic [wait_bits-1:0] write_wait_counter;
logic [3:0] read_beats;
logic [3:0] write_beats;

always_comb begin
    case (read_state)
    READ_STATE_ADDRESS:
        next_read_state = bus.arvalid & bus.arready ? READ_STATE_LATENCY_WAIT :
            READ_STATE_ADDRESS;
    READ_STATE_LATENCY_WAIT:
        next_read_state = ~|read_wait_counter ? READ_STATE_DATA :
            READ_STATE_LATENCY_WAIT;
    READ_STATE_DATA:
        next_read_state = bus.rlast ? READ_STATE_ADDRESS : READ_STATE_DATA;
    default:
        next_read_state = READ_STATE_ADDRESS;
    endcase
end

always_ff @(posedge clk)
    read_state <= next_read_state;

always_ff @(posedge clk)
    if (read_state == READ_STATE_LATENCY_WAIT)
        read_wait_counter <= read_wait_counter - 1'b1;
    else
        read_wait_counter <= wait_bits'(latency) - 1'b1;
    
always_ff @(posedge clk) begin
    case (next_read_state)
    READ_STATE_ADDRESS: begin
        read_beats <= 'b0;
        bus.rlast <= 1'b0;
        bus.rvalid <= 1'b0;
        bus.arready <= 1'b1;
    end
    READ_STATE_LATENCY_WAIT:
        bus.arready <= 1'b0;
    READ_STATE_DATA: begin
        bus.rvalid <= 1'b1;
        if (read_state == READ_STATE_LATENCY_WAIT || (bus.rready && bus.rvalid))
            bus.rdata <= $c("this->bus->read(",
                            bus.raddr + addr_bits'(read_beats) * 4, ");");
        if (bus.rlen == 'b0 ||
            ((bus.rvalid & bus.rready) && read_beats == bus.rlen))
            bus.rlast <= 1'b1;
    end
    default: ;
    endcase
end

always_ff @(posedge clk)
    if (next_read_state == READ_STATE_DATA)
        read_beats <= 'b1;
    else if (read_state == READ_STATE_DATA)
        read_beats <= bus.rvalid & bus.rready ? read_beats + 1'b1 : read_beats;
    else
        read_beats <= 'b0;

always_comb begin
    case (write_state)
    WRITE_STATE_ADDRESS:
        next_write_state = bus.awvalid & bus.awready ?
            WRITE_STATE_LATENCY_WAIT : WRITE_STATE_ADDRESS;
    WRITE_STATE_LATENCY_WAIT:
        next_write_state = ~|write_wait_counter ?
            WRITE_STATE_DATA : WRITE_STATE_LATENCY_WAIT;
    WRITE_STATE_DATA:
        next_write_state = bus.wlast ? WRITE_STATE_ACK : WRITE_STATE_DATA;
    WRITE_STATE_ACK:
        next_write_state = bus.bvalid & bus.bready ?
            WRITE_STATE_ADDRESS : WRITE_STATE_ACK;
    endcase
end

always_ff @(posedge clk)
    write_state <= next_write_state;

always_ff @(posedge clk)
    if (write_state == WRITE_STATE_LATENCY_WAIT)
        write_wait_counter <= write_wait_counter - 1'b1;
    else
        write_wait_counter <= wait_bits'(latency) - 1'b1;

always_ff @(posedge clk) begin
    case (next_write_state)
    WRITE_STATE_ADDRESS: begin
        write_beats <= 'b0;
        bus.wready <= 1'b0;
        bus.awready <= 1'b1;
        bus.bvalid <= 1'b0;
    end
    WRITE_STATE_LATENCY_WAIT:
        bus.awready <= 1'b0;
    WRITE_STATE_DATA: begin
        bus.wready <= 1'b1;
        if (bus.wlen == 'b0 ||
            ((bus.wvalid & bus.wready) && write_beats == bus.wlen - 1'b1))
            assert(bus.wlast);
    end
    WRITE_STATE_ACK: begin
        bus.bvalid <= 1'b1;
        bus.wready <= 1'b0;
    end
    default: ;
    endcase
end

always_ff @(posedge clk)
    if (write_state == WRITE_STATE_DATA && bus.wvalid && bus.wready)
        $c("this->bus->write(", bus.waddr + addr_bits'(write_beats) * 4,
            ", ", bus.wdata, ", ", bus.wstb, ");");

always_ff @(posedge clk)
    if (write_state == WRITE_STATE_DATA)
        write_beats <= bus.wvalid & bus.wready ? write_beats + 1'b1 :
            write_beats;
    else
        write_beats <= 'b0;

`systemc_header
#include <memory>
#include "MemoryDevice.h"
`systemc_interface
std::shared_ptr<AbstractMemoryBus> bus;
void set_bus(std::shared_ptr<AbstractMemoryBus> bus)
{
    this->bus = bus;
}
`verilog
endmodule
