module BusTransactor #(
    integer latency     = 2,
    integer words       = 512,
    logic   instruction = 0
) (
    input logic                    clk,
          MemInterface.Subordinate bus
);
    typedef enum bit [1:0] {
        READ_STATE_ADDRESS,
        READ_STATE_LATENCY_WAIT,
        READ_STATE_DATA
    } read_state_t;

    typedef enum bit [1:0] {
        WRITE_STATE_ADDRESS,
        WRITE_STATE_LATENCY_WAIT,
        WRITE_STATE_DATA,
        WRITE_STATE_ACK
    } write_state_t;

    localparam wait_bits = $clog2(latency);
    localparam addr_bits = $clog2(words);

    write_state_t write_state, next_write_state;
    read_state_t read_state, next_read_state;

    logic   [wait_bits-1:0] read_wait_counter;
    logic   [wait_bits-1:0] write_wait_counter;
    logic   [          3:0] read_beats;
    logic   [          3:0] write_beats  /* verilator public */;

    chandle                 bus_handle;

    task dpi_set_bus;
        input chandle handle;

        bus_handle = handle;
    endtask

    export "DPI-C" task dpi_set_bus;

    import "DPI-C" function bit [31:0] bus_read(
        input chandle        handle,
        input bit     [31:0] address,
        input bit            instruction
    );

    import "DPI-C" function void bus_write(
        input chandle        handle,
        input bit     [31:0] address,
        input bit     [31:0] data,
        input bit     [ 3:0] wstb
    );

    always_comb begin
        case (read_state)
            READ_STATE_ADDRESS: begin
                next_read_state = bus.arvalid & bus.arready ? READ_STATE_LATENCY_WAIT :
            READ_STATE_ADDRESS;
            end
            READ_STATE_LATENCY_WAIT: begin
                next_read_state = ~|read_wait_counter ? READ_STATE_DATA : READ_STATE_LATENCY_WAIT;
            end
            READ_STATE_DATA: begin
                next_read_state = bus.rlast ? READ_STATE_ADDRESS : READ_STATE_DATA;
            end
            default: begin
                next_read_state = READ_STATE_ADDRESS;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        read_state <= next_read_state;
    end

    always_ff @(posedge clk) begin
        if (read_state == READ_STATE_LATENCY_WAIT) begin
            read_wait_counter <= read_wait_counter - 1'b1;
        end else begin
            read_wait_counter <= wait_bits'(latency) - 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        case (next_read_state)
            READ_STATE_ADDRESS: begin
                read_beats  <= 'b0;
                bus.rlast   <= 1'b0;
                bus.rvalid  <= 1'b0;
                bus.arready <= 1'b1;
            end
            READ_STATE_LATENCY_WAIT: begin
                bus.arready <= 1'b0;
            end
            READ_STATE_DATA: begin
                bus.rvalid <= 1'b1;
                if (read_state == READ_STATE_LATENCY_WAIT || (bus.rready && bus.rvalid)) begin
                    bus.rdata <=
                        bus_read(bus_handle, bus.raddr + addr_bits'(read_beats) * 4, instruction);
                end
                if (bus.rlen == 'b0 || ((bus.rvalid & bus.rready) && read_beats == bus.rlen)) begin
                    bus.rlast <= 1'b1;
                end
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (read_state == READ_STATE_LATENCY_WAIT && next_read_state == READ_STATE_DATA) begin
            read_beats <= 'b1;
        end else if (read_state == READ_STATE_DATA) begin
            read_beats <= bus.rvalid & bus.rready ? read_beats + 1'b1 : read_beats;
        end else begin
            read_beats <= 'b0;
        end
    end

    always_comb begin
        case (write_state)
            WRITE_STATE_ADDRESS: begin
                next_write_state = bus.awvalid & bus.awready ?
            WRITE_STATE_LATENCY_WAIT : WRITE_STATE_ADDRESS;
            end
            WRITE_STATE_LATENCY_WAIT: begin
                next_write_state = ~|write_wait_counter ? WRITE_STATE_DATA : WRITE_STATE_LATENCY_WAIT;
            end
            WRITE_STATE_DATA: begin
                next_write_state = bus.wlast ? WRITE_STATE_ACK : WRITE_STATE_DATA;
            end
            WRITE_STATE_ACK: begin
                next_write_state = bus.bvalid & bus.bready ? WRITE_STATE_ADDRESS : WRITE_STATE_ACK;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        write_state <= next_write_state;
    end

    always_ff @(posedge clk) begin
        if (write_state == WRITE_STATE_LATENCY_WAIT) begin
            write_wait_counter <= write_wait_counter - 1'b1;
        end else begin
            write_wait_counter <= wait_bits'(latency) - 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        case (next_write_state)
            WRITE_STATE_ADDRESS: begin
                write_beats <= 'b0;
                bus.wready  <= 1'b0;
                bus.awready <= 1'b1;
                bus.bvalid  <= 1'b0;
            end
            WRITE_STATE_LATENCY_WAIT: begin
                bus.awready <= 1'b0;
            end
            WRITE_STATE_DATA: begin
                bus.wready <= 1'b1;
                if (bus.wlen == 'b0 || ((bus.wvalid & bus.wready) && write_beats == bus.wlen)) begin
                    assert (bus.wlast);
                end
            end
            WRITE_STATE_ACK: begin
                bus.bvalid <= 1'b1;
                bus.wready <= 1'b0;
            end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (write_state == WRITE_STATE_DATA && bus.wvalid && bus.wready) begin
            bus_write(bus_handle, bus.waddr + addr_bits'(write_beats) * 4, bus.wdata, bus.wstb);
            assert (|bus.wstb);
        end
    end

    always_ff @(posedge clk) begin
        if (write_state == WRITE_STATE_DATA) begin
            write_beats <= bus.wvalid & bus.wready ? write_beats + 1'b1 : write_beats;
        end else begin
            write_beats <= 'b0;
        end
    end

endmodule
