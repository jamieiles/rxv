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
        input bvalid
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
        output bvalid
    );

endinterface
