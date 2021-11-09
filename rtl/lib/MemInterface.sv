interface MemInterface;

    // verilator lint_off UNUSED
    logic [31:0] waddr;
    logic [31:0] raddr;
    // verilator lint_on UNUSED
    logic        awready;
    logic        awvalid;
    logic        arready;
    logic        arvalid;
    logic        wvalid;
    logic        wready;
    logic        rvalid;
    logic        rready;
    logic [ 3:0] wstb;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        wlast;
    logic        rlast;
    logic [ 3:0] rlen;
    logic [ 3:0] wlen;
    logic        bready;
    logic        bvalid;

    modport Manager(
        output waddr,
        output raddr,
        input awready,
        output awvalid,
        input arready,
        output arvalid,
        output rlen,
        output wlen,
        output wvalid,
        input wready,
        output wdata,
        output wstb,
        output wlast,
        input rvalid,
        output rready,
        input rdata,
        input rlast,
        output bready,
        input bvalid,
        import ar_ack,
        import aw_ack,
        import read_beat_ack,
        import write_beat_ack,
        import write_ack
    );

    modport Subordinate(
        input waddr,
        input raddr,
        output awready,
        input awvalid,
        output arready,
        input arvalid,
        input rlen,
        input wlen,
        input wvalid,
        output wready,
        input wstb,
        input wdata,
        input wlast,
        output rvalid,
        input rready,
        output rdata,
        output rlast,
        input bready,
        output bvalid,
        import ar_ack,
        import aw_ack,
        import read_beat_ack,
        import write_beat_ack,
        import write_ack
    );

    function read_beat_ack;
        read_beat_ack = rready & rvalid;
    endfunction

    function write_beat_ack;
        write_beat_ack = wready & wvalid;
    endfunction

    function ar_ack;
        ar_ack = arready & arvalid;
    endfunction

    function aw_ack;
        aw_ack = awready & awvalid;
    endfunction

    function write_ack;
        write_ack = bready & bvalid;
    endfunction

endinterface
